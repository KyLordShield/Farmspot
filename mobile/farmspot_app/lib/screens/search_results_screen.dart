import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/farm_pin.dart';
import '../models/listing.dart';
import '../services/farm_service.dart';
import '../services/listing_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/crop_icons.dart';
import '../widgets/home_widgets.dart';
import '../widgets/search_widgets.dart';
import 'product_detail_screen.dart';

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
  final String query;

  final Future<List<Listing>> Function(String term) loadResults;

  final Future<LatLng> Function() loadPosition;

  final Future<List<FarmPin>> Function() loadFarms;

  const SearchResultsScreen({
    super.key,
    required this.query,
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

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  SearchSortMode _sort = SearchSortMode.nearest;

  List<_ResultRow> _rows = const [];
  bool _loading = true;
  String? _error;

  /// Farm id -> distance in km from the buyer's position (null when unknown,
  /// e.g. the farm has no coordinates or wasn't resolvable).
  Map<String, double> _distances = const {};

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
      final listings = await widget.loadResults(widget.query);

      // Distance data behind the "Nearest" sort: buyer position + public farm
      // pins. Both calls are failure-tolerant (fallback position / empty list),
      // so results still render when distances can't be resolved.
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

      final rows = listings.map((listing) {
        final crop = listing.toCropListing();
        final km = distances[crop.farmId];
        return _ResultRow(
          item: SearchResultItem(
            crop: crop.cropName,
            seller: crop.farmName,
            distance: km != null
                ? LocationService.distanceLabel(km)
                : 'Distance unavailable',
            icon: cropIconForCrop(crop.cropName, crop.cropType),
            imageUrl: crop.imageUrl,
            listingId: crop.listingId,
            farmId: crop.farmId,
          ),
          listing: crop,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _distances = distances;
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

  /// Nearest: ascending straight-line distance (unknowns sink to the end).
  /// Available: AVAILABLE_NOW first, then SOON_TO_HARVEST, then everything else.
  List<_ResultRow> get _sortedRows {
    final sorted = List<_ResultRow>.of(_rows);
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
    for (final row in _rows) {
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
      return const Center(child: CircularProgressIndicator());
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

    final rows = _sortedRows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        SearchResultsToolbar(
          sort: _sort,
          onSortChanged: (mode) => setState(() => _sort = mode),
          onFiltersTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Filters coming soon.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        _buildCountLine(rows.length),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No farms selling this crop yet.',
                style: TextStyle(color: Colors.black54, fontSize: 14),
              ),
            ),
          )
        else
          SearchResultGrid(
            items: rows.map((r) => r.item).toList(growable: false),
            onTap: _onCardTap,
          ),
      ],
    );
  }

  Widget _buildCountLine(int count) {
    final noun = count == 1 ? 'farm' : 'farms';
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
            '$count $noun selling $_displayTitle near you',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
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
              _displayTitle,
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