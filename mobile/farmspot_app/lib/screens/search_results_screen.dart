import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/crop_category.dart';
import '../models/farm_pin.dart';
import '../models/listing.dart';
import '../models/listing_review.dart';
import '../models/search_crop_group.dart';
import '../services/farm_service.dart';
import '../services/listing_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/crop_icons.dart';
import '../widgets/home_widgets.dart';
import '../widgets/search_widgets.dart';
import '../widgets/lottie_loader.dart';
import 'product_detail_screen.dart';

/// Radius boundary for the "Nearest" view, in kilometers. Results from farms
/// within this distance show under "Near you"; everything farther is grouped
/// under "Other farms" so buyers still see every match, just organized.
const double searchRadiusKm = 15.0;

String get _searchRadiusLabel => '${searchRadiusKm.toStringAsFixed(0)} km';

/// Radius for the MIXED image-search list, in kilometers.
///
/// >>> CHANGE THIS to move the "more than N km away" divider. <<<
///
/// Image search only. Deliberately separate from [searchRadiusKm] so the
/// text/category search split ("Near you" / "Other farms") is untouched.
const double imageSearchRangeKm = 10.0;

/// Gap between image-search cards, and the screen's side margin. The photo is
/// the whole point of this screen, so the cards run nearly edge to edge with
/// barely a seam between them. Text search keeps its roomier defaults.
const double _imageGridGap = 4;
const double _imageGridSideMargin = 4;

/// Taller cells than the text-search default (0.78): more of the card is the
/// photo, less is text.
const double _imageGridAspectRatio = 0.72;

EdgeInsets get _imageListPadding => const EdgeInsets.fromLTRB(
  _imageGridSideMargin,
  12,
  _imageGridSideMargin,
  24,
);

/// Two results closer than this (km) are treated as "the same distance", so
/// the tie is broken by detection confidence instead of floating-point noise.
const double _imageSearchTieKm = 0.1;

String get _imageSearchRangeLabel => imageSearchRangeKm.toStringAsFixed(0);

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
/// The [loadResults] / [loadBuyerPosition] / [loadFarms] callbacks are
/// injectable for tests, mirroring the MapScreen pattern. Defaults hit the real
/// endpoints.
class SearchResultsScreen extends StatefulWidget {
  /// The raw term submitted by the buyer (what gets searched AND logged).
  /// Used when [groups] is empty (single-crop search).
  final String query;

  /// Multiple crops found in one photo (image search). When non-empty, the
  /// screen renders ONE mixed list of every matching listing from all of these
  /// groups, sorted nearest-farm-first, with the matching crop shown per card.
  final List<SearchCropGroup> groups;

  /// Detection confidence (0..1) per crop display title, in the order the
  /// detector returned them (strongest first). Used for the card chip and as
  /// the tie-break when two farms are equally distant. Empty is fine: results
  /// then fall back to the group's position and sort purely by distance.
  final List<(String, double)> detectionConfidences;

  final Future<List<Listing>> Function(String term) loadResults;

  final Future<List<FarmPin>> Function() loadFarms;

  /// Real GPS fix, or null when location permission was denied or the fix
  /// failed. Every distance on this screen is measured from it, for text search
  /// as well as image search.
  ///
  /// Null has to be answerable, because the alternative is measuring from a
  /// hardcoded anchor: "Distance unavailable" on every card is honest and
  /// fixable by the buyer, where a confident "12 km away" measured from a point
  /// that is not them is neither. Test seam.
  final Future<LatLng?> Function() loadBuyerPosition;

  const SearchResultsScreen({
    super.key,
    required this.query,
    this.groups = const [],
    this.detectionConfidences = const [],
    this.loadResults = _defaultLoadResults,
    this.loadFarms = FarmService.fetchPublicFarms,
    this.loadBuyerPosition = LocationService.tryBuyerPosition,
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
  final CropListing listing;

  const _ResultRow({required this.listing});
}

/// One flattened entry in the mixed image-search list.
///
/// A listing matched by several detected crops appears exactly once, carrying
/// the crop whose detection scored highest ([confidence]) plus the display
/// title of the group it was found through ([cropTitle]).
class _ImageResult {
  final CropListing listing;

  /// English display title of the crop that matched, e.g. "Cabbage".
  final String cropTitle;

  /// Detection confidence 0..1 for that crop, used for the card chip and as
  /// the tie-breaker when two farms are effectively the same distance away.
  final double confidence;

  const _ImageResult({
    required this.listing,
    required this.cropTitle,
    required this.confidence,
  });

  /// Copy with a replaced listing, used when the reviews block reports that this
  /// listing's average changed while its detail screen was open.
  _ImageResult copyWithListing(CropListing listing) => _ImageResult(
    listing: listing,
    cropTitle: cropTitle,
    confidence: confidence,
  );
}

/// Order + range-split for the mixed image-search list.
///
/// [hasLocation] false means GPS is unavailable: no distances are shown and
/// the list falls back to detection confidence. In that case [inRange] is
/// empty and no divider is drawn.
class _ImageOrdering {
  final List<_ImageResult> inRange;
  final List<_ImageResult> outOfRange;
  final bool hasLocation;

  const _ImageOrdering({
    required this.inRange,
    required this.outOfRange,
    required this.hasLocation,
  });
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  SearchSortMode _sort = SearchSortMode.nearest;

  List<_ResultRow> _rows = const [];

  /// Flattened, deduped list for image search. One entry per listing, whatever
  /// the number of detected crops that matched it.
  List<_ImageResult> _imageResults = const [];

  /// True when the buyer's position is a real GPS fix. False means
  /// permission was denied or GPS failed, so distances are omitted and the
  /// list falls back to detection confidence.
  bool _hasLocation = false;

  /// True while the position lookup is still in flight — the common case being
  /// an unanswered permission dialog. While it is true no distance is known,
  /// and the screen must not print a "within 15 km" claim or a near/far split
  /// derived from distances that have not arrived yet.
  bool _locating = false;

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
      var rows = const <_ResultRow>[];
      var imageResults = const <_ImageResult>[];

      // Detection confidence per group title. The detector returns crops
      // already sorted strongest-first, so the first occurrence wins.
      final confidenceByTitle = <String, double>{};
      for (final crop in widget.detectionConfidences) {
        confidenceByTitle.putIfAbsent(crop.$1, () => crop.$2);
      }

      if (_multi) {
        // Flatten EVERY detected crop into ONE list, like a lens search.
        // Alias terms are still fetched per group (so a "kamatis" surfaces
        // "Tomato" listings) but dedup is now GLOBAL rather than per-section,
        // so a listing matched by two crops shows once, keeping the crop with
        // the higher detection confidence.
        final bestByListingId = <String, _ImageResult>{};
        for (final group in widget.groups) {
          final confidence = confidenceByTitle[group.title] ?? 0;
          final seenInGroup = <String>{};
          for (final term in group.terms) {
            final listings = await widget.loadResults(term);
            for (final listing in listings) {
              // Same listing twice from this group's own aliases: skip.
              if (!seenInGroup.add(listing.id)) continue;
              final crop = listing.toCropListing();
              final existing = bestByListingId[listing.id];
              // Already found via another crop: keep the higher confidence.
              if (existing != null && existing.confidence >= confidence) {
                continue;
              }
              bestByListingId[listing.id] = _ImageResult(
                listing: crop,
                cropTitle: group.title,
                confidence: confidence,
              );
            }
          }
        }
        imageResults = bestByListingId.values.toList();
      } else {
        final listings = await widget.loadResults(widget.query);
        // Only the listing is kept. The card payload is built at render time by
        // [_itemFor], because the distance on it is not knowable until the farms
        // endpoint has answered — a card built here had nothing to show but a
        // placeholder.
        rows = listings
            .map((listing) => _ResultRow(listing: listing.toCropListing()))
            .toList();
      }

      // Both lists ask for a REAL fix, so neither measures from the Cebu
      // fallback anchor. Image search worked this way already; text search used
      // to resolve a position that always came back as that fallback, so a buyer
      // with GPS off was shown a confident "12 km away" measured from a point
      // that is not them.
      //
      // The lookup starts here but is NOT awaited before the first render. On a
      // fresh install it ends in a permission dialog, and a results grid that
      // waits on a dialog is a grid the buyer never sees until they answer it.
      // So results render now with no distances, and [_applyBuyerPosition] fills
      // them in when the lookup settles.
      final positionLookup = widget.loadBuyerPosition();
      final farms = await widget.loadFarms();

      if (!mounted) return;
      setState(() {
        _rows = rows;
        if (_multi) {
          _imageResults = imageResults;
        }
        _categories = categories;
        if (_activeCategoryId != null &&
            !_categories.any((c) => c.id == _activeCategoryId)) {
          _activeCategoryId = null;
        }
        _loading = false;
        _locating = true;
      });

      _applyBuyerPosition(await positionLookup, farms);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Turns the buyer's fix into the per-farm distance map and repaints.
  ///
  /// Runs after the results are already on screen, so it must never throw: a
  /// failed lookup costs distances, not the page.
  void _applyBuyerPosition(LatLng? fix, List<FarmPin> farms) {
    if (!mounted) return;
    try {
      // With no real fix there is nothing to measure from, so nothing is
      // measured. Leaving the map empty rather than filling it from the fallback
      // anchor matters: the anchor is a real coordinate, so a farm sitting on top
      // of it would otherwise come back as "0 m away" — the most confident wrong
      // answer available. Every consumer treats a missing entry as unknown.
      final distances = <String, double>{
        if (fix != null)
          for (final farm in farms)
            if (farm.id.isNotEmpty &&
                (farm.latitude != 0 || farm.longitude != 0))
              farm.id: LocationService.distanceKm(
                fix,
                LatLng(farm.latitude, farm.longitude),
              ),
      };
      setState(() {
        _distances = distances;
        _hasLocation = fix != null;
        _locating = false;
      });
    } catch (_) {
      setState(() {
        _distances = const {};
        _hasLocation = false;
        _locating = false;
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
        sorted.sort((a, b) => _kmFor(a).compareTo(_kmFor(b)));
      case SearchSortMode.available:
        sorted.sort(
          (a, b) => _statusRank(
            b.listing.status,
          ).compareTo(_statusRank(a.listing.status)),
        );
    }
    return sorted;
  }

  double _kmFor(_ResultRow row) {
    final farmId = row.listing.farmId;
    if (farmId == null) return double.infinity;
    return _distances[farmId] ?? double.infinity;
  }

  /// The card payload for a text-search row, built at render time.
  ///
  /// Distance and status were the two fields this used to get wrong. The row is
  /// created the moment listings arrive, which is before any farm coordinate is
  /// known, so a card built then had nothing to print but "Distance
  /// unavailable" — permanently, on every text search result, while image search
  /// (which builds its cards after the same lookup) showed real numbers. The
  /// status was simply never copied across, so text results had no "Available
  /// now" pill while image results did, from the identical card widget.
  ///
  /// Deriving the item here means the card always reflects what the screen
  /// currently knows, including a rating that came back from a review written
  /// on the detail screen.
  SearchResultItem _itemFor(_ResultRow row) {
    final crop = row.listing;
    final km = _kmFor(row);

    return SearchResultItem(
      crop: crop.cropName,
      seller: crop.farmName,
      distance: km.isFinite ? _formatDistanceKm(km) : 'Distance unavailable',
      status: crop.status,
      icon: cropIconForCrop(crop.cropName, crop.cropType),
      imageUrl: crop.imageUrl,
      listingId: crop.listingId,
      farmId: crop.farmId,
      ratings: crop.ratings,
    );
  }

  static int _statusRank(String status) {
    return switch (status) {
      'AVAILABLE_NOW' => 2,
      'SOON_TO_HARVEST' => 1,
      _ => 0,
    };
  }

  /// Distance from the buyer to an image-search result's farm, or infinity
  /// when the farm has no usable coordinates.
  double _imageKm(_ImageResult result) {
    final farmId = result.listing.farmId;
    if (farmId == null) return double.infinity;
    return _distances[farmId] ?? double.infinity;
  }

  /// Orders the mixed image-search list and splits it at [imageSearchRangeKm].
  ///
  /// With a real GPS fix: nearest first, and within [_imageSearchTieKm] of each
  /// other the higher detection confidence wins, so two neighbouring farms
  /// don't flip order on rounding noise. Farms whose distance is unknown sort
  /// to the end (they cannot be meaningfully "within" a radius).
  ///
  /// Without a fix: confidence order, no split, so the caller knows to omit
  /// the divider entirely.
  _ImageOrdering _orderImageResults() {
    if (!_hasLocation) {
      final byConfidence = List<_ImageResult>.of(_imageResults)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      return _ImageOrdering(
        inRange: byConfidence,
        outOfRange: const [],
        hasLocation: false,
      );
    }

    final sorted = List<_ImageResult>.of(_imageResults)
      ..sort((a, b) {
        final ka = _imageKm(a);
        final kb = _imageKm(b);
        if ((ka - kb).abs() <= _imageSearchTieKm) {
          return b.confidence.compareTo(a.confidence);
        }
        return ka.compareTo(kb);
      });

    return _ImageOrdering(
      inRange: sorted
          .where(
            (r) => _imageKm(r).isFinite && _imageKm(r) <= imageSearchRangeKm,
          )
          .toList(),
      outOfRange: sorted
          .where(
            (r) => !(_imageKm(r).isFinite && _imageKm(r) <= imageSearchRangeKm),
          )
          .toList(),
      hasLocation: true,
    );
  }

  void _onCardTap(SearchResultItem item) {
    // Real results carry the listing id; find the CropListing and open the real
    // ProductDetailScreen. Defensive no-op fallback for edge/legacy rows.
    if (_multi) {
      for (final result in _imageResults) {
        if (result.listing.listingId != null &&
            result.listing.listingId == item.listingId) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                listing: result.listing,
                onRatingsChanged: (summary) =>
                    _applyRating(result.listing, summary),
              ),
            ),
          );
          return;
        }
      }
    } else {
      for (final row in _rows) {
        if (row.listing.listingId != null &&
            row.listing.listingId == item.listingId) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                listing: row.listing,
                onRatingsChanged: (summary) =>
                    _applyRating(row.listing, summary),
              ),
            ),
          );
          return;
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Listing detail is unavailable.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Swaps a fresh average onto the card the buyer came from.
  ///
  /// Same reasoning as the home feed: these rows were built from the search
  /// response and kept their copy of the average, so a review written on the
  /// detail screen left the result card reading the old score until the buyer
  /// searched again.
  ///
  /// Only the [CropListing] needs patching now. The card payload is derived from
  /// it by [_itemFor] on every build, so the text-search card and the image-search
  /// card both follow from this one copy.
  void _applyRating(CropListing listing, RatingSummary summary) {
    final listingId = listing.listingId;
    if (!mounted || listingId == null || listingId.isEmpty) return;

    setState(() {
      _rows = [
        for (final row in _rows)
          if (row.listing.listingId == listingId)
            _ResultRow(listing: row.listing.withRatings(summary))
          else
            row,
      ];
      _imageResults = [
        for (final result in _imageResults)
          if (result.listing.listingId == listingId)
            result.copyWithListing(result.listing.withRatings(summary))
          else
            result,
      ];
    });
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
            Icon(
              Icons.tune,
              size: 16,
              color: name == null
                  ? AppColors.primaryGreen
                  : AppColors.warningAmber,
            ),
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
      return const Center(child: FarmLottieLoading());
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
      children.add(
        Padding(
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
        ),
      );
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

      if (_locating) {
        // The lookup is still out — usually an OS permission dialog waiting on
        // the buyer. Every distance is unknown, so a "within 15 km" line or a
        // near/far split would be a guess about a location nobody has reported
        // yet. Show the results and let the distances land when they can.
        children.add(const SizedBox(height: 8));
        children.add(_buildCountLine(rows.length));
        children.add(const SizedBox(height: 14));
        children.add(_resultGrid(rows.map(_itemFor).toList(growable: false)));
      } else if (!_hasLocation && other.isNotEmpty) {
        // No GPS fix, so every distance is unknown. Splitting on an unknown
        // radius would put everything under "Other farms" and print "no farms
        // within 15 km of you" — a claim about the buyer's location that was
        // never established. Say what is actually true and show the results.
        children.add(
          const Text(
            'Distances need location access, which is off — showing every '
            'result instead.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        );
        children.add(const SizedBox(height: 14));
        children.add(_buildSectionHeader('All results'));
        children.add(const SizedBox(height: 10));
        children.add(_resultGrid(rows.map(_itemFor).toList(growable: false)));
      } else if (near.isEmpty && other.isNotEmpty) {
        children.add(
          Text(
            'No farms selling $_displayTitle within $_searchRadiusLabel of you',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        );
        children.add(const SizedBox(height: 14));
        children.add(_buildSectionHeader('All results'));
        children.add(const SizedBox(height: 10));
        children.add(_resultGrid(rows.map(_itemFor).toList(growable: false)));
      } else {
        children.add(_buildCountLine(near.length, within: true));
        children.add(const SizedBox(height: 14));
        children.add(_buildSectionHeader('Near you'));
        children.add(const SizedBox(height: 10));
        children.add(_resultGrid(near.map(_itemFor).toList(growable: false)));
        if (other.isNotEmpty) {
          children.add(const SizedBox(height: 22));
          children.add(_buildSectionHeader('Other farms'));
          children.add(const SizedBox(height: 10));
          children.add(
            _resultGrid(other.map(_itemFor).toList(growable: false)),
          );
        }
      }
    } else {
      children.add(_buildCountLine(rows.length));
      children.add(const SizedBox(height: 14));
      children.add(_resultGrid(rows.map(_itemFor).toList(growable: false)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: children,
    );
  }

  /// Image search: ONE mixed list of every listing from every detected crop,
  /// nearest farm first, with no per-crop sections or headers.
  ///
  /// Layout follows the range split: in-range results, then a full-width
  /// non-tappable divider naming the range from [imageSearchRangeKm], then the
  /// farther results (still shown, still nearest-first). When nothing is in
  /// range the divider moves to the top. With no GPS fix there are no
  /// distances and no divider, just a note and confidence order.
  Widget _buildMultiBody() {
    final ordering = _orderImageResults();
    final cropCount = widget.groups.length;
    final children = <Widget>[];

    children.add(const SizedBox(height: 4));
    children.add(
      Text(
        cropCount == 1
            ? '1 crop found in your photo'
            : '$cropCount crops found in your photo',
        style: const TextStyle(color: Colors.black54, fontSize: 13),
      ),
    );

    // No trustworthy position: say so once, and drop distances rather than
    // inventing them from the fallback city.
    if (!ordering.hasLocation) {
      children.add(const SizedBox(height: 8));
      children.add(
        const _ImageSearchNote(
          'Turn on location to see the closest farms first.',
        ),
      );
      children.add(const SizedBox(height: 6));
      if (ordering.inRange.isEmpty) {
        children.add(_buildImageEmptyState());
        return ListView(padding: _imageListPadding, children: children);
      }
      children.add(
        _imageGrid(_imageItems(ordering.inRange, showDistance: false)),
      );
      return ListView(padding: _imageListPadding, children: children);
    }

    children.add(const SizedBox(height: 8));
    children.add(_buildImageCountLine(ordering.inRange.length, within: true));
    children.add(const SizedBox(height: 12));

    // All results are beyond the range: divider first, far results still shown.
    if (ordering.inRange.isEmpty) {
      if (ordering.outOfRange.isNotEmpty) {
        children.add(_buildImageRangeDivider());
        children.add(const SizedBox(height: 12));
      }
      if (ordering.outOfRange.isEmpty) {
        children.add(_buildImageEmptyState());
      } else {
        children.add(_imageGrid(_imageItems(ordering.outOfRange)));
      }
      return ListView(padding: _imageListPadding, children: children);
    }

    children.add(_imageGrid(_imageItems(ordering.inRange)));

    if (ordering.outOfRange.isNotEmpty) {
      children.add(const SizedBox(height: 22));
      children.add(_buildImageRangeDivider());
      children.add(const SizedBox(height: 12));
      children.add(_imageGrid(_imageItems(ordering.outOfRange)));
    }

    return ListView(padding: _imageListPadding, children: children);
  }

  /// One image-search grid, always with the same density. Every grid in
  /// [_buildMultiBody] goes through here so they cannot drift apart.
  SearchResultGrid _imageGrid(List<SearchResultItem> items) {
    return SearchResultGrid(
      items: items,
      onTap: _onCardTap,
      gap: _imageGridGap,
      cardAspectRatio: _imageGridAspectRatio,
    );
  }

  /// One text-search grid, same density as [_imageGrid]. The card is the same
  /// widget on both screens, so matching gap and aspect ratio is what makes the
  /// thumbnail and the status pill land in the same spot with the same size
  /// instead of only looking alike.
  SearchResultGrid _resultGrid(List<SearchResultItem> items) {
    return SearchResultGrid(
      items: items,
      onTap: _onCardTap,
      gap: _imageGridGap,
      cardAspectRatio: _imageGridAspectRatio,
    );
  }

  /// Builds card payloads for the mixed list, formatting the real distance
  /// when one is known.
  List<SearchResultItem> _imageItems(
    List<_ImageResult> results, {
    bool showDistance = true,
  }) {
    return [
      for (final result in results)
        SearchResultItem(
          crop: result.listing.cropName,
          seller: result.listing.farmName,
          distance: showDistance && _imageKm(result).isFinite
              ? _formatDistanceKm(_imageKm(result))
              : 'Distance unavailable',
          status: result.listing.status,
          icon: cropIconForCrop(
            result.listing.cropName,
            result.listing.cropType,
          ),
          imageUrl: result.listing.imageUrl,
          listingId: result.listing.listingId,
          farmId: result.listing.farmId,
          ratings: result.listing.ratings,
        ),
    ];
  }

  /// Meters under 1 km, one decimal above it, so "450 m away" / "1.2 km away".
  static String _formatDistanceKm(double km) {
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  /// The full-width, non-tappable divider between in-range and far results.
  /// The distance comes from [imageSearchRangeKm] so changing that one
  /// constant updates this text too.
  Widget _buildImageRangeDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0)),
          bottom: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_off_outlined,
            size: 15,
            color: Colors.black38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Farms beyond this point are more than '
              '$_imageSearchRangeLabel km away',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCountLine(int count, {bool within = false}) {
    final noun = count == 1 ? 'farm' : 'farms';
    final cropNoun = widget.groups.length == 1
        ? (widget.groups.first.title.toLowerCase())
        : 'crops';
    // Image search reports its own range ([imageSearchRangeKm], the same
    // constant the divider uses). It used to borrow text search's
    // searchRadiusKm, which made the count say "within 15 km" right above a
    // divider saying "more than 10 km away".
    final suffix = within
        ? 'within $_imageSearchRangeLabel km of you'
        : 'near you';
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
            '$count $noun selling $cropNoun $suffix',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildImageEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'No farms selling these crops yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildCountLine(int count, {bool within = false}) {
    final noun = count == 1 ? 'farm' : 'farms';
    final suffix = within ? 'within $_searchRadiusLabel of you' : 'near you';
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

/// Small informational line above the mixed image-search list (used for the
/// "turn on location" hint). Non-tappable.
class _ImageSearchNote extends StatelessWidget {
  final String text;

  const _ImageSearchNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_disabled_outlined,
            size: 15,
            color: Colors.black45,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
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

  const _CategoryFilterSheet({required this.categories, this.selectedId});

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
              const Icon(
                Icons.circle_outlined,
                color: Colors.black26,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
