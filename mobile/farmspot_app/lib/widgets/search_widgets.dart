import 'package:flutter/material.dart';
import '../models/listing_review.dart';
import '../theme.dart';
import 'home_widgets.dart' show cropStatusData;
import 'rating_stars.dart';
import 'listing_grid_layout.dart';

/// How many farm/seller rows a search preview shows before "See all". Shared by
/// the typeahead and the results screen so both cap at the same number.
const int searchPreviewCap = 4;

/// A single search result card payload. Used both by the image-search mockup
/// (placeholder-only entries) and — for the live Search screen — built from a
/// real [CropListing] with an optional [imageUrl] and the [listingId]/[farmId]
/// needed to open the real ProductDetail / Farm Profile screens.
class SearchResultItem {
  final String crop;

  /// Free-form seller label, e.g. "Little A's Farm".
  final String seller;

  /// Pre-formatted distance label, e.g. "0.4 km away".
  final String distance;

  /// Listing status, used for the availability badge on the card. Null hides
  /// the badge, which is how the text/category search behaves today.
  final String? status;

  final IconData icon;

  /// Real listing photo URL; null for placeholder entries.
  final String? imageUrl;

  /// Backend listing id, present only on real-data items.
  final String? listingId;

  final String? farmId;

  /// Star average and visible review count, carried so a search card shows the
  /// same rating the home card does. Defaults to none, which renders nothing —
  /// the mockup entries above have no rating and must not grow a fake star row.
  final RatingSummary ratings;

  const SearchResultItem({
    required this.crop,
    required this.seller,
    required this.distance,
    this.status,
    this.icon = Icons.eco,
    this.imageUrl,
    this.listingId,
    this.farmId,
    this.ratings = const RatingSummary.none(),
  });

  /// Copy with a new [ratings] summary.
  ///
  /// The search card draws [ratings] and the detail screen draws the summary its
  /// reviews block reports, so a review written on the detail screen left the
  /// card it was opened from showing the old average. Every field is restated
  /// rather than spread, same as `CropListing.withRatings`.
  SearchResultItem withRatings(RatingSummary ratings) => SearchResultItem(
    crop: crop,
    seller: seller,
    distance: distance,
    status: status,
    icon: icon,
    imageUrl: imageUrl,
    listingId: listingId,
    farmId: farmId,
    ratings: ratings,
  );
}

/// Hardcoded 2x2 grid data used by both the typed-results screen and the
/// image-search results step (they share the same uniform grid treatment).
const List<SearchResultItem> mockSearchResults = [
  SearchResultItem(
    crop: 'Carrots',
    seller: "Little A's Farm",
    distance: '0.4 km away',
    icon: Icons.center_focus_strong,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Big Ben Farm',
    distance: '0.7 km away',
    icon: Icons.flare,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Sun Village Farm',
    distance: '1.2 km away',
    icon: Icons.eco,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Green Hollow Farm',
    distance: '1.8 km away',
    icon: Icons.spa,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Ridge Top Farm',
    distance: '2.4 km away',
    icon: Icons.landscape,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Cedar Spring Farm',
    distance: '3.1 km away',
    icon: Icons.grain,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Twin Hills Farm',
    distance: '3.9 km away',
    icon: Icons.terrain,
  ),
  SearchResultItem(
    crop: 'Carrots',
    seller: 'Meadow Fresh Farm',
    distance: '4.6 km away',
    icon: Icons.water_drop,
  ),
];

/// Sort modes for the result chips. Visually selectable only — no real
/// ordering logic in this mockup.
enum SearchSortMode { nearest, available, soonToHarvest }

extension SearchSortModeLabel on SearchSortMode {
  String get label => switch (this) {
    SearchSortMode.nearest => 'Nearest',
    SearchSortMode.available => 'Available',
    SearchSortMode.soonToHarvest => 'Soon to harvest',
  };
}

/// Uniform result cards with two to four columns based on available width.
class SearchResultGrid extends StatelessWidget {
  final List<SearchResultItem> items;
  final void Function(SearchResultItem)? onTap;

  /// Gap between cards. Image search tightens this so photos fill the screen;
  /// text search keeps the roomier default so its sparser cards breathe.
  final double gap;

  /// Width/height of each cell. Smaller means taller, so a bigger photo for
  /// the same footer text.
  final double cardAspectRatio;

  const SearchResultGrid({
    super.key,
    required this.items,
    this.onTap,
    this.gap = 12,
    this.cardAspectRatio = 0.78,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: listingGridColumns(constraints.maxWidth),
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: cardAspectRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return SearchResultCard(
            item: item,
            onTap: onTap == null ? null : () => onTap!(item),
          );
        },
      ),
    );
  }
}

/// A single result card: dominant image placeholder on top — soft gradient,
/// big icon inside a frosted disc, and a distance pill overlaid on the corner —
/// with only crop name + farm underneath. No status badge, no stacked info.
class SearchResultCard extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback? onTap;

  const SearchResultCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.fieldBorder.withValues(alpha: 0.4),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl != null &&
                        item.imageUrl!.trim().isNotEmpty)
                      Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 600,
                        errorBuilder: (context, error, stackTrace) =>
                            const _GradientFill(),
                      )
                    else
                      const _GradientFill(),
                    if (item.imageUrl == null || item.imageUrl!.trim().isEmpty)
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            item.icon,
                            size: 34,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    // Availability badge, same top-left pill Home uses on its
                    // crop cards so the two grids read identically.
                    if (item.status != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _StatusBadge(status: item.status!),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.near_me,
                              size: 12,
                              color: AppColors.primaryGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.distance,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.crop,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront,
                        size: 13,
                        color: AppColors.mutedGreen,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.seller,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Rating, same treatment as the home card: hidden entirely
                  // until something has been rated, so a search result and the
                  // feed listing for the same crop read identically.
                  CompactRatingLabel(summary: item.ratings, size: 12.5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The toolbar that sits above the results grid: a segmented Nearest /
/// Nearest ordering and exclusive availability filters, plus category filters.
class SearchResultsToolbar extends StatelessWidget {
  final SearchSortMode sort;
  final ValueChanged<SearchSortMode> onSortChanged;
  final VoidCallback? onFiltersTap;

  /// Optional replacement for the Filter chip, e.g. a "Not this?" correction
  /// link on the image-search results step.
  final Widget? trailing;

  const SearchResultsToolbar({
    super.key,
    required this.sort,
    required this.onSortChanged,
    this.onFiltersTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // Flexible + scale-down lets the segmented control shrink instead of
    // overflowing on narrow screens or with wide (accessibility/test) fonts;
    // the trailing chip keeps its natural size and hugs the right edge.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _SegmentedSort(sort: sort, onChanged: onSortChanged),
          ),
        ),
        const SizedBox(width: 12),
        trailing ??
            GestureDetector(
              onTap: onFiltersTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3EEDD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 16, color: AppColors.primaryGreen),
                    SizedBox(width: 5),
                    Text(
                      'Filters',
                      style: TextStyle(
                        color: AppColors.primaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// A segmented pill control: one track, two selectable options. The selected
/// side fills green; the other stays transparent.
class _SegmentedSort extends StatelessWidget {
  final SearchSortMode sort;
  final ValueChanged<SearchSortMode> onChanged;

  const _SegmentedSort({required this.sort, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0E4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(SearchSortMode.nearest),
          _segment(SearchSortMode.available),
          _segment(SearchSortMode.soonToHarvest),
        ],
      ),
    );
  }

  Widget _segment(SearchSortMode mode) {
    final isSelected = sort == mode;
    return GestureDetector(
      onTap: () => onChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Availability pill overlaid on a result card's photo. Delegates the
/// label + colour mapping to [cropStatusData] so the badge matches Home and
/// the seller flow exactly rather than restating the three cases here.
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final data = cropStatusData(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: data.color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        data.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The soft green gradient filler behind a result card's image area (used
/// when a listing has no photo, or when a photo fails to load).
class _GradientFill extends StatelessWidget {
  const _GradientFill();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE3EEDD), Color(0xFFC9DFC9)],
        ),
      ),
    );
  }
}

/// Heading for one search preview group ("Farms", "Sellers") with an optional
/// "See all" affordance. When [onSeeAll] is null the row is just a label, so
/// the same widget serves a capped preview and a full "See all" list.
class SearchPreviewHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const SearchPreviewHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.primaryGreen,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One farm row in a search preview or a "See all farms" list: cover photo,
/// name, and a "N listings · barangay" subtitle. Dumb on purpose — it takes
/// primitives so it does not need to know about the FarmPin model.
class FarmSearchRow extends StatelessWidget {
  final String name;
  final String? barangay;
  final int activeListingsCount;
  final String? photoUrl;
  final VoidCallback onTap;

  const FarmSearchRow({
    super.key,
    required this.name,
    required this.onTap,
    this.barangay,
    this.activeListingsCount = 0,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              _Thumb(photoUrl: photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedGreen,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final listings = activeListingsCount == 1
        ? '1 listing'
        : '$activeListingsCount listings';
    final place = barangay?.trim();
    if (place == null || place.isEmpty) return listings;
    return '$listings · $place';
  }
}

/// One seller row: avatar, name, and a "N farms · M listings" subtitle. Takes
/// primitives for the same reason as [FarmSearchRow].
class SellerSearchRow extends StatelessWidget {
  final String name;
  final int farmCount;
  final int activeListingsCount;

  /// Real profile photo of the seller, or null to fall back to initials.
  final String? photoUrl;

  final VoidCallback onTap;

  const SellerSearchRow({
    super.key,
    required this.name,
    required this.onTap,
    this.farmCount = 0,
    this.activeListingsCount = 0,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              _InitialAvatar(initial: _initials(name), photoUrl: photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedGreen,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final farms = farmCount == 1 ? '1 farm' : '$farmCount farms';
    final listings = activeListingsCount == 1
        ? '1 listing'
        : '$activeListingsCount listings';
    return '$farms · $listings';
  }

  /// First letters of up to two words ("Rejean Libando" -> "RL"). Falls back
  /// to the first character, and to a neutral glyph for a blank name.
  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Circular avatar for a person row: the real profile photo when there is one,
/// an initials disc otherwise (and while the photo loads or if it fails).
class _InitialAvatar extends StatelessWidget {
  final String initial;
  final String? photoUrl;

  const _InitialAvatar({required this.initial, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    if (url == null || url.isEmpty) return _initials();

    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: 200,
          errorBuilder: (_, _, _) => _initials(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _initials(),
        ),
      ),
    );
  }

  Widget _initials() {
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.primaryGreen,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// Rounded 44px thumbnail for a farm row, with the eco placeholder when the
/// farm has no photo (or the photo fails to load).
class _Thumb extends StatelessWidget {
  final String? photoUrl;

  const _Thumb({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null || url.isEmpty
            ? const _GradientFill()
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 200,
                errorBuilder: (context, error, stackTrace) =>
                    const _GradientFill(),
              ),
      ),
    );
  }
}
