import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../theme.dart';
import 'seller_widgets.dart';

/// Data model for a crop listing shown in the Home feed.
class CropListing {
  final String cropName;
  final String farmName;
  final String cropType;
  final String distance;
  final String status;
  final String barangay;
  final String sitio;
  final String postedLabel;
  final String expiresLabel;
  final String contactNumber;
  final String? imageUrl;
  final String? description;
  final List<String> photoUrls;
  final String? listingId;
  final String? farmId;
  final IconData placeholderIcon;

  /// Real crop_category id (e.g. "LEAFVG"). Null for listings with no
  /// category; used by Home/Search category filters.
  final String? categoryId;

  const CropListing({
    required this.cropName,
    required this.farmName,
    this.cropType = 'Vegetable',
    this.distance = '0.4 km away',
    this.status = 'P_status',
    this.barangay = 'Brgy. Sudlon',
    this.sitio = 'Sitio Maraag',
    this.postedLabel = 'today',
    this.expiresLabel = '3 days',
    this.contactNumber = '0900-000-0000',
    this.imageUrl,
    this.description,
    this.photoUrls = const [],
    this.listingId,
    this.farmId,
    this.categoryId,
    this.placeholderIcon = Icons.eco,
  });
}

/// Rounded green square placeholder used when a listing has no photo yet.
class CropImagePlaceholder extends StatelessWidget {
  final double size;
  final IconData icon;
  final double borderRadius;

  const CropImagePlaceholder({
    super.key,
    required this.size,
    this.icon = Icons.eco,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.fieldBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Icon(icon, color: AppColors.primaryGreen, size: size * 0.5),
    );
  }
}

/// Human-readable label + color for a listing's status, matching the
/// convention used across the seller flow (MyFarmScreen status sheet).
({String label, Color color}) cropStatusData(String status) {
  return switch (status) {
    'AVAILABLE_NOW' => (label: 'Available Now', color: AppColors.primaryGreen),
    'SOON_TO_HARVEST' => (label: 'Soon to Harvest', color: Colors.orange),
    _ => (label: 'Not Available', color: Colors.grey),
  };
}

/// Search bar + camera icon shown inside the green home header.
///
/// When [tapToOpen] is true the bar acts as a single tappable button that
/// fires [onSearchTap] (no inline typing), so the whole bar routes to the
/// dedicated SearchScreen instead of submitting a query in place.
class HomeSearchField extends StatelessWidget {
  final VoidCallback? onCameraTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onSearchTap;
  final bool tapToOpen;

  const HomeSearchField({
    super.key,
    this.onCameraTap,
    this.controller,
    this.onSubmitted,
    this.onSearchTap,
    this.tapToOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final searchIcon = Icon(
      Icons.search,
      color: Colors.black45,
    );

    // In tap-to-open mode the whole bar (icon + hint area) is a single button.
    // We don't render a TextField at all: a TextField consumes the tap to place
    // a cursor even when readOnly, so the GestureDetector behind it would never
    // fire. A plain hint text has no gesture of its own.
    final leftSide = tapToOpen
        ? Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSearchTap,
              child: Row(
                children: [
                  searchIcon,
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Search Crops or farms',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.black45, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          )
        : Expanded(
            child: Row(
              children: [
                searchIcon,
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: onSubmitted,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search Crops or farms',
                      hintStyle:
                          TextStyle(color: Colors.black45, fontSize: 14),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          leftSide,
          GestureDetector(
            onTap: onCameraTap,
            child: const Icon(Icons.camera_alt_outlined, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped filter chip ("All", "Leafy Vegetables", ...).
class CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGreen : AppColors.fieldBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.fieldBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Marketplace-style card for a single crop listing: full-width square photo
/// on top (with real photo or icon placeholder), status badge overlaid on the
/// image corner, then one-line truncated crop name + farm/distance below.
class CropCard extends StatelessWidget {
  final CropListing listing;
  final VoidCallback onTap;

  const CropCard({super.key, required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = cropStatusData(listing.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.fieldBorder.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: _buildImage(),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status.color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Two lines so real 1-3 word crop names fully display;
                  // anything genuinely longer still truncates with an ellipsis.
                  Text(
                    listing.cropName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${listing.farmName} - ${listing.distance}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final url = listing.imageUrl;
    if (url == null || url.trim().isEmpty) {
      return Container(
        color: AppColors.fieldBackground,
        child: Icon(
          listing.placeholderIcon,
          size: 48,
          color: AppColors.primaryGreen,
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 600,
      errorBuilder: (context, error, stackTrace) => Container(
        color: AppColors.fieldBackground,
        child: Icon(
          listing.placeholderIcon,
          size: 48,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }
}

/// Ladder layout for the Home feed: the first two cards sit side by side,
/// then every following card steps diagonally to the right like ladder rungs
/// before wrapping back to the left margin. Capped at a phone-like max width
/// so the cascade stays bounded on wide (Chrome) screens.
class CropLadderGrid extends StatelessWidget {
  final List<CropListing> listings;
  final ValueChanged<CropListing> onTap;

  const CropLadderGrid({
    super.key,
    required this.listings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const gap = 8.0;
            const rowShift = 4.0;
            const rowGap = 10.0;

            final rows = <Widget>[];
            for (var i = 0; i < listings.length; i += 2) {
              final left = listings[i];
              final hasRight = i + 1 < listings.length;
              final right = hasRight ? listings[i + 1] : null;
              final isFirstRow = i == 0;

              // Each card gets a fixed fraction of the *indent-adjusted* width.
              // Fixed (not Expanded) so a lone leftover card can never stretch
              // across the whole row.
              final cardWidth = (width - (isFirstRow ? 0 : rowShift) - gap) / 2;

              rows.add(
                // Each pair is a "rung". Rows after the first sit one step
                // further right and one step lower — the ladder descent.
                // Inside each rung the two cards stay perfectly aligned.
                Padding(
                  padding: EdgeInsets.only(
                    left: isFirstRow ? 0 : rowShift,
                    top: isFirstRow ? 0 : rowGap,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: CropCard(
                          listing: left,
                          onTap: () => onTap(left),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (right != null)
                        SizedBox(
                          width: cardWidth,
                          child: CropCard(
                            listing: right,
                            onTap: () => onTap(right),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            );
          },
        ),
      ),
    );
  }
}

/// Two-column responsive grid of [CropCard]s. Capped at a phone-like max width
/// so the same 2-column layout stays clean on wide (Chrome) screens.
class CropCardGrid extends StatelessWidget {
  final List<CropListing> listings;
  final ValueChanged<CropListing> onTap;

  const CropCardGrid({
    super.key,
    required this.listings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        // Masonry (staggered) grid: each card sizes to its own content, so a
        // 2-line name in one column never forces a fixed cell height that would
        // overflow on device fonts the way a childAspectRatio grid did.
        child: MasonryGridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: listings.length,
          itemBuilder: (context, index) {
            final listing = listings[index];
            return CropCard(
              listing: listing,
              onTap: () => onTap(listing),
            );
          },
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
        ),
      ),
    );
  }
}

/// Bottom navigation bar: Home, Map, Insights, Profile.
class FarmSpotBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FarmSpotBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 8,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(kBuyerTabs.length, (i) {
            final selected = i == currentIndex;
            final color = selected ? AppColors.primaryGreen : Colors.black45;
            return GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(kBuyerTabs[i].$1, color: color, size: 24),
                  const SizedBox(height: 2),
                  Text(
                    kBuyerTabs[i].$2,
                    style: TextStyle(color: color, fontSize: 11),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
