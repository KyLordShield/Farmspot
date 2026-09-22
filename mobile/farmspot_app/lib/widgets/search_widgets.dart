import 'package:flutter/material.dart';
import '../theme.dart';

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

  final IconData icon;

  /// Real listing photo URL; null for placeholder entries.
  final String? imageUrl;

  /// Backend listing id, present only on real-data items.
  final String? listingId;

  final String? farmId;

  const SearchResultItem({
    required this.crop,
    required this.seller,
    required this.distance,
    this.icon = Icons.eco,
    this.imageUrl,
    this.listingId,
    this.farmId,
  });
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
enum SearchSortMode { nearest, available }

extension SearchSortModeLabel on SearchSortMode {
  String get label => switch (this) {
        SearchSortMode.nearest => 'Nearest',
        SearchSortMode.available => 'Available',
      };
}

/// Uniform, evenly-aligned 2x2 grid of result cards. Deliberately NOT the
/// staggered/masonry feel of Home — a more "visual browsing" mode with a
/// dominant image per card and minimal text underneath.
class SearchResultGrid extends StatelessWidget {
  final List<SearchResultItem> items;
  final void Function(SearchResultItem)? onTap;

  const SearchResultGrid({
    super.key,
    required this.items,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.88,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return SearchResultCard(
          item: item,
          onTap: onTap == null ? null : () => onTap!(item),
        );
      },
    );
  }
}

/// A single result card: dominant image placeholder on top — soft gradient,
/// big icon inside a frosted disc, and a distance pill overlaid on the corner —
/// with only crop name + farm underneath. No status badge, no stacked info.
class SearchResultCard extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback? onTap;

  const SearchResultCard({
    super.key,
    required this.item,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.fieldBorder.withValues(alpha: 0.4)),
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
                    if (item.imageUrl != null && item.imageUrl!.trim().isNotEmpty)
                      Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 600,
                        errorBuilder: (context, error, stackTrace) =>
                            const _GradientFill(),
                      )
                    else
                      const _GradientFill(),
                    if (item.imageUrl == null ||
                        item.imageUrl!.trim().isEmpty)
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
/// Available sort control plus a Filters action chip. Both are visual-only in
/// this mockup — the segmented control toggles its own state and the Filters
/// chip just fires [onFiltersTap] for the screen to handle (or ignore).
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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