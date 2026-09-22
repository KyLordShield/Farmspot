import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/crop_category.dart';
import '../models/farm_pin.dart';
import '../models/listing.dart';
import '../models/search_crop_group.dart';
import '../services/farm_service.dart';
import '../services/listing_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/crop_icons.dart';
import '../widgets/home_widgets.dart';
import '../widgets/search_widgets.dart';
import '../widgets/farmspot_loader.dart';
import 'product_detail_screen.dart';

/// Radius boundary for the "Nearest" view, in kilometers. Results from farms
/// within this distance show under "Near you"; everything farther is grouped
/// under "Other farms" so buyers still see every match, just organized.
const double searchRadiusKm = 15.0;

String get _searchRadiusLabel => '${searchRadiusKm.toStringAsFixed(0)} km';

/// Screen 2 of the search flow: real results for a submitted search term.
///
/// Unlike the image-search step (still a mockup), this screen is fully live:
/// it reuses the SAME /api/listings?search= call the web feed uses — WITHOUT
/// the ?suggest=1 opt-out — so the backend logs the submitted term into
/// search_log exactly as before, feeding the existing Top Searched analytics.
///
/// The "Nearest" / "Available" chips sort the already-fetched set client-side:
/// Nearest uses a haversine distance from the buyer's position to each
/// listing's farm (the same latlong2.Distance math the Map screen uses), and
/// Available just bumps AVAILABLE_NOW listings to the front. No new backend
/// call is made when a chip is toggled.
///
/// The [loadResults] / [loadPosition] / [loadFarms] callbacks are injectable
/// for tests, mirroring the MapScreen pattern. Defaults hit the real endpoints.
class SearchResultsScreen extends StatefulWidget {
  /// The raw term submitted by the buyer (what gets searched AND logged).
  /// Used when [groups] is empty (single-crop search).
  final String query;

  /// Multiple crops found in one photo (image search). When non-empty, the
  /// screen renders one section per crop's [SearchCropGroup], merging that
  /// group's alias terms (e.g. "Kamatis" + "Tomato") into a deduped section.
  final List<SearchCropGroup> groups;

  final Future<List<Listing>> Function(String term) loadResults;

  final Future<LatLng> Function() loadPosition;

  final Future<List<FarmPin>> Function() loadFarms;

  const SearchResultsScreen({
    super.key,
    required this.query,
    this.groups = const [],
    this.loadResults = _defaultLoadResults,
    this.loadPosition = LocationService.defaultBuyerPosition,
    this.loadFarms = FarmService.fetchPublicFarms,
  });

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

/// Default results loader: the existing feed search WITHOUT the ?suggest=1
/// opt-out, so a real submitted search logs into search_log exactly as before.
Future<List<Listing>> _defaultLoadResults(String term) {
  return ListingService.fetchListings(search: term);
}

class _ResultRow {
  final SearchResultItem item;
  final CropListing listing;

  const _ResultRow({required this.item, required this.listing});
}

class _ResultSection {
  final String title;
  final List<_ResultRow> rows;

  const _ResultSection({required this.title, required this.rows});
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  SearchSortMode _sort = SearchSortMode.nearest;

  List<_ResultRow> _rows = const [];

  /// One section per crop when [SearchResultsScreen.queries] is non-empty.
  List<_ResultSection> _sections = const [];
  bool _loading = true;
  String? _error;

  /// Real crop categories for the Filters sheet (empty if they couldn't load).
  List<CropCategory> _categories = [];

  /// Selected category id, or null for "All".
  String? _activeCategoryId;

  /// Farm id -> distance in km from the buyer's position (null when unknown,
  /// e.g. the farm has no coordinates or wasn't resolvable).
  Map<String, double> _distances = const {};

  /// True when showing one section per detected crop (image search).
  bool get _multi => widget.groups.isNotEmpty;

  String get _displayTitle {
    final t = widget.query.trim();
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Category list for the Filters sheet. Failure-tolerant: an empty list
      // just leaves the sheet with "All" only, results still render fine.
      var categories = <CropCategory>[];
      try {
        categories = await ListingService.fetchCropCategories();
      } catch (_) {}

      // Distance data behind the "Nearest" sort: buyer position + public farm
      // pins. Both calls are failure-tolerant (fallback position / empty list),
      // so results still render when distances can't be resolved. Loaded AFTER
      // the results themselves so a slow/failed term lookup fails fast.
      final sections = _multi ? <_ResultSection>[] : null;
      var rows = const <_ResultRow>[];

      if (_multi) {
        // One section per crop group: fetch every alias term the group knows
        // (e.g. "kamatis" and "tomato") and merge into a deduped section so a
        // photo of a kamatis shows BOTH the Kamatis and the Tomato listings.
        for (final group in widget.groups) {
          final seen = <String>{};
          final mapped = <_ResultRow>[];
          for (final term in group.terms) {
            final listings = await widget.loadResults(term);
            for (final listing in listings) {
              if (!seen.add(listing.id)) continue; // same listing from another alias
              final crop = listing.toCropListing();
              mapped.add(_ResultRow(
                item: SearchResultItem(
                  crop: crop.cropName,
                  seller: crop.farmName,
                  distance: 'Distance unavailable',
                  icon: cropIconForCrop(crop.cropName, crop.cropType),
                  imageUrl: crop.imageUrl,
                  listingId: crop.listingId,
                  farmId: crop.farmId,
                ),
                listing: crop,
              ));
            }
          }
          sections!.add(_ResultSection(title: group.title, rows: mapped));
        }
      } else {
        final listings = await widget.loadResults(widget.query);
        rows = listings.map((listing) {
          final crop = listing.toCropListing();
          return _ResultRow(
            item: SearchResultItem(
              crop: crop.cropName,
              seller: crop.farmName,
              distance: 'Distance unavailable',
              icon: cropIconForCrop(crop.cropName, crop.cropType),
              imageUrl: crop.imageUrl,
              listingId: crop.listingId,
              farmId: crop.farmId,
            ),
            listing: crop,
          );
        }).toList();
      }

      final position = await widget.loadPosition();
      final farms = await widget.loadFarms();
      final distances = <String, double>{
        for (final farm in farms)
          if (farm.id.isNotEmpty &&
              (farm.latitude != 0 || farm.longitude != 0))
            farm.id: LocationService.distanceKm(
              position,
              LatLng(farm.latitude, farm.longitude),
            ),
      };

      if (!mounted) return;
      setState(() {
        _rows = rows;
        if (_multi && sections != null) {
          _sections = sections;
        }
        _distances = distances;
        _categories = categories;
        if (_activeCategoryId != null &&
            !_categories.any((c) => c.id == _activeCategoryId)) {
          _activeCategoryId = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Rows narrowed by the active category filter (null id = All). The raw
  /// [_rows] keeps every fetched result; only the visible subset is sorted.
  List<_ResultRow> get _visibleRows {
    if (_activeCategoryId == null) return _rows;
    return _rows
        .where((r) => r.listing.categoryId == _activeCategoryId)
        .toList();
  }

  String? get _activeCategoryName {
    for (final c in _categories) {
      if (c.id == _activeCategoryId) return c.name;
    }
    return null;
  }

  /// Nearest: ascending straight-line distance (unknowns sink to the end).
  /// Available: AVAILABLE_NOW first, then SOON_TO_HARVEST, then everything else.
  List<_ResultRow> get _sortedRows {
    final sorted = List<_ResultRow>.of(_visibleRows);
    switch (_sort) {
      case SearchSortMode.nearest:
        sorted.sort((a, b) =>
            _kmFor(a).compareTo(_kmFor(b)));
      case SearchSortMode.available:
        sorted.sort((a, b) =>
            _statusRank(b.listing.status).compareTo(_statusRank(a.listing.status)));
    }
    return sorted;
  }

  double _kmFor(_ResultRow row) {
    final farmId = row.listing.farmId;
    if (farmId == null) return double.infinity;
    return _distances[farmId] ?? double.infinity;
  }

  static int _statusRank(String status) {
    return switch (status) {
      'AVAILABLE_NOW' => 2,
      'SOON_TO_HARVEST' => 1,
      _ => 0,
    };
  }

  void _onCardTap(SearchResultItem item) {
    // Real results carry the listing id; find the CropListing and open the real
    // ProductDetailScreen. Defensive no-op fallback for edge/legacy rows.
    final rows = _multi
        ? [for (final s in _sections) ...s.rows]
        : _rows;
    for (final row in rows) {
      if (row.item.listingId != null &&
          row.item.listingId == item.listingId) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(listing: row.listing),
          ),
        );
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Listing detail is unavailable.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Opens the category picker; a chosen category narrows the results
  /// client-side (no extra backend call). Empty selection means "All".
  Future<void> _openCategoryFilters() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryFilterSheet(
        categories: _categories,
        selectedId: _activeCategoryId,
      ),
    );

    if (picked == null || !mounted) return;
    setState(() => _activeCategoryId = picked.isEmpty ? null : picked);
  }

  /// The Filters chip: shows "Filters" normally, or the active category name
  /// with a green dot when a filter is applied.
  Widget _buildFilterChip() {
    final name = _activeCategoryName;
    return GestureDetector(
      onTap: _openCategoryFilters,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE3EEDD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune,
                size: 16,
                color: name == null
                    ? AppColors.primaryGreen
                    : AppColors.warningAmber),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                name ?? 'Filters',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: name == null
                      ? AppColors.primaryGreen
                      : AppColors.warningAmber,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (name != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.warningAmber,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const FarmSpotLoader();
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.black38),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_multi) {
      return _buildMultiBody();
    }

    final rows = _sortedRows;
    final children = <Widget>[
      SearchResultsToolbar(
        sort: _sort,
        onSortChanged: (mode) => setState(() => _sort = mode),
        trailing: _buildFilterChip(),
      ),
      const SizedBox(height: 14),
    ];

    if (rows.isEmpty) {
      children.add(_buildCountLine(rows.length));
      children.add(const SizedBox(height: 14));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            _activeCategoryId != null && _rows.isNotEmpty
                ? 'No ${(_activeCategoryName ?? 'crop').toLowerCase()} '
                    'crops listed right now.'
                : 'No farms selling this crop yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ),
      ));
    } else if (_sort == SearchSortMode.nearest) {
      // Group by the radius boundary: "Near you" then "Other farms". When the
      // nearest results are all beyond the boundary (or unknown), just show
      // everything with an honest count line instead of hiding it.
      final near = rows
          .where((r) => _kmFor(r).isFinite && _kmFor(r) <= searchRadiusKm)
          .toList();
      final other = rows
          .where((r) => !(_kmFor(r).isFinite && _kmFor(r) <= searchRadiusKm))
          .toList();

      if (near.isEmpty && other.isNotEmpty) {
        children.add(Text(
          'No farms selling $_displayTitle within $_searchRadiusLabel of you',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ));
        children.add(const SizedBox(height: 14));
        children.add(_buildSectionHeader('All results'));
        children.add(const SizedBox(height: 10));
        children.add(SearchResultGrid(
          items: rows.map((r) => r.item).toList(growable: false),
          onTap: _onCardTap,
        ));
      } else {
        children.add(_buildCountLine(near.length, within: true));
        children.add(const SizedBox(height: 14));
        children.add(_buildSectionHeader('Near you'));
        children.add(const SizedBox(height: 10));
        children.add(SearchResultGrid(
          items: near.map((r) => r.item).toList(growable: false),
          onTap: _onCardTap,
        ));
        if (other.isNotEmpty) {
          children.add(const SizedBox(height: 22));
          children.add(_buildSectionHeader('Other farms'));
          children.add(const SizedBox(height: 10));
          children.add(SearchResultGrid(
            items: other.map((r) => r.item).toList(growable: false),
            onTap: _onCardTap,
          ));
        }
      }
    } else {
      children.add(_buildCountLine(rows.length));
      children.add(const SizedBox(height: 14));
      children.add(SearchResultGrid(
        items: rows.map((r) => r.item).toList(growable: false),
        onTap: _onCardTap,
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: children,
    );
  }

  /// Multi-crop view (image search): one section per detected crop, each
  /// sorted nearest-first and headed by the crop name count line. No radius
  /// split — all farms for that crop render in one nearest-sorted grid.
  Widget _buildMultiBody() {
    final children = <Widget>[
      const SizedBox(height: 4),
      Text(
        _sections.length == 1
            ? '${_sections.length} crop found in your photo'
            : '${_sections.length} crops found in your photo',
        style: const TextStyle(color: Colors.black54, fontSize: 13),
      ),
      const SizedBox(height: 8),
    ];

    for (final section in _sections) {
      final sorted = List<_ResultRow>.of(section.rows)
        ..sort((a, b) => _kmFor(a).compareTo(_kmFor(b)));
      children.add(const SizedBox(height: 10));
      children.add(_buildSectionHeader(section.title));
      children.add(const SizedBox(height: 8));
      if (sorted.isEmpty) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              'No farms selling this crop yet.',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ),
        ));
      } else {
        children.add(_sort == SearchSortMode.available
            ? _buildCountLine(sorted.length)
            : _buildCountLine(sorted.length, within: true));
        children.add(const SizedBox(height: 10));
        children.add(SearchResultGrid(
          items: sorted.map((r) => r.item).toList(growable: false),
          onTap: _onCardTap,
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: children,
    );
  }

  Widget _buildCountLine(int count, {bool within = false}) {
    final noun = count == 1 ? 'farm' : 'farms';
    final suffix =
        within ? 'within $_searchRadiusLabel of you' : 'near you';
    return Row(
      children: [
        Container(
          width: 5,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$count $noun selling $_displayTitle $suffix',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            color: Colors.black87,
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              _multi ? 'From photo' : _displayTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet category picker for the Search results. Returns '' for "All"
/// or a category id; `null` when dismissed.
class _CategoryFilterSheet extends StatelessWidget {
  final List<CropCategory> categories;
  final String? selectedId;

  const _CategoryFilterSheet({
    required this.categories,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.darkGreen,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Show only crops from one category.',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _option(context, '', 'All'),
                  for (final category in categories)
                    _option(context, category.id, category.name),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, String id, String label) {
    final isSelected = selectedId == id || (id.isEmpty && selectedId == null);
    return InkWell(
      onTap: () => Navigator.of(context).pop(id),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.black87, fontSize: 15),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primaryGreen,
                size: 20,
              )
            else
              const Icon(Icons.circle_outlined,
                  color: Colors.black26, size: 20),
          ],
        ),
      ),
    );
  }
}