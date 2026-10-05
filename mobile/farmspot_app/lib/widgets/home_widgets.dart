import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/listing_review.dart';
import '../theme.dart';
import 'rating_stars.dart';
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

  /// FMR_ID of the seller behind this listing, so the product detail screen can
  /// offer "Report seller" as well as "Report listing" — two different
  /// accusations that need two different ids.
  final String? farmerId;

  /// Star average and visible review count for this listing.
  ///
  /// Defaults to [RatingSummary.none] so every existing caller — the seeded
  /// fixtures in tests, the my-farm rows — keeps compiling and renders no
  /// stars, which is the correct display for a listing nobody has reviewed.
  final RatingSummary ratings;

  const CropListing({
    required this.cropName,
    required this.farmName,
    this.cropType = 'Vegetable',
    this.distance = '0.4 km away',
    this.status = 'P_status',
    this.barangay = 'Brgy. Sudlon',
    this.sitio = '',
    this.postedLabel = 'today',
    this.expiresLabel = '3 days',
    this.contactNumber = '0900-000-0000',
    this.imageUrl,
    this.description,
    this.photoUrls = const [],
    this.listingId,
    this.farmId,
    this.categoryId,
    this.farmerId,
    this.ratings = const RatingSummary.none(),
    this.placeholderIcon = Icons.eco,
  });

  /// Copy with a new [ratings] summary, used when the product detail screen
  /// reports that a review was written or edited for this listing.
  ///
  /// Every field is restated rather than spread, same as [withDistance]: a field
  /// added later must not be silently dropped from the copy.
  CropListing withRatings(RatingSummary ratings) => CropListing(
    cropName: cropName,
    farmName: farmName,
    cropType: cropType,
    distance: distance,
    status: status,
    barangay: barangay,
    sitio: sitio,
    postedLabel: postedLabel,
    expiresLabel: expiresLabel,
    contactNumber: contactNumber,
    imageUrl: imageUrl,
    description: description,
    photoUrls: photoUrls,
    listingId: listingId,
    farmId: farmId,
    categoryId: categoryId,
    farmerId: farmerId,
    ratings: ratings,
    placeholderIcon: placeholderIcon,
  );

  /// Copy with an overridden [distance] label (used by the feed to swap the
  /// seeded placeholder for the real haversine distance once buyer GPS is known).
  ///
  /// Every field is restated rather than spread, so a field added later cannot
  /// be silently dropped from this copy — a missing [ratings] here would make
  /// a rated listing show no stars once the feed knew the distance.
  CropListing withDistance(String distance) => CropListing(
    cropName: cropName,
    farmName: farmName,
    cropType: cropType,
    distance: distance,
    status: status,
    barangay: barangay,
    sitio: sitio,
    postedLabel: postedLabel,
    expiresLabel: expiresLabel,
    contactNumber: contactNumber,
    imageUrl: imageUrl,
    description: description,
    photoUrls: photoUrls,
    listingId: listingId,
    farmId: farmId,
    categoryId: categoryId,
    farmerId: farmerId,
    ratings: ratings,
    placeholderIcon: placeholderIcon,
  );
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

  /// Bar height. Lowered on Home so the notifications and messages buttons fit
  /// beside it without squeezing the bar into something unreadable.
  final double height;

  const HomeSearchField({
    super.key,
    this.onCameraTap,
    this.controller,
    this.onSubmitted,
    this.onSearchTap,
    this.tapToOpen = false,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final searchIcon = Icon(Icons.search, color: Colors.black45);

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
                      hintStyle: TextStyle(color: Colors.black45, fontSize: 14),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height >= 46 ? 14 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height / 2),
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
          border: Border.all(
            color: AppColors.fieldBorder.withValues(alpha: 0.6),
          ),
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
                AspectRatio(aspectRatio: 1, child: _buildImage()),
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
                Positioned(
                  bottom: 8,
                  right: 8,
                  // Distance sits on the image rather than in the text block:
                  // it describes where the photo was taken, and putting it under
                  // the farm name made every card's second line
                  // "Farm - 0.4 km away", which is the least scannable place for
                  // the one number that varies between two otherwise identical
                  // cards. Overlaying it on the image also leaves the line below
                  // the crop name free for the rating.
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(10),
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
                          size: 11,
                          color: AppColors.primaryGreen,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          listing.distance,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                    listing.farmName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  // Only rendered once something has been rated. Height is
                  // reserved as a SizedBox.shrink (zero) when not, so a card
                  // in a masonry column does not jump as reviews arrive.
                  // Next to the crop name rather than over the image, because
                  // it is metadata about the listing and not about the photo.
                  CompactRatingLabel(summary: listing.ratings, size: 12.5),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < listings.length; i += 2)
                  buildLadderRung(
                    left: listings[i],
                    right: i + 1 < listings.length ? listings[i + 1] : null,
                    width: constraints.maxWidth,
                    isFirstRung: i == 0,
                    onTap: onTap,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One rung of the ladder: two cards side by side, or a lone card.
///
/// Shared by the eager grid and the paged feed so the geometry cannot drift.
/// [width] is the indent-adjusted width the two cards must share; [right] is
/// null for the odd card out, which stays at the same width as any other rather
/// than stretching across the rung.
Widget buildLadderRung({
  required CropListing left,
  required CropListing? right,
  required double width,
  required bool isFirstRung,
  required ValueChanged<CropListing> onTap,
}) {
  // Each card gets a fixed fraction of the *indent-adjusted* width. Fixed (not
  // Expanded) so a lone leftover card can never stretch across the whole row.
  final cardWidth =
      (width - (isFirstRung ? 0 : _kLadderRowShift) - _kLadderGap) / 2;

  return Padding(
    padding: EdgeInsets.only(
      left: isFirstRung ? 0 : _kLadderRowShift,
      top: isFirstRung ? 0 : _kLadderRowGap,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: cardWidth,
          child: CropCard(listing: left, onTap: () => onTap(left)),
        ),
        const SizedBox(width: 8),
        if (right != null)
          SizedBox(
            width: cardWidth,
            child: CropCard(listing: right, onTap: () => onTap(right)),
          ),
      ],
    ),
  );
}

const double _kLadderGap = 8.0;
const double _kLadderRowShift = 4.0;
const double _kLadderRowGap = 10.0;

/// The ladder as a sliver, so a long feed builds only what is on screen.
///
/// [CropLadderGrid] is a Column of rungs inside a scroll view, which means the
/// whole feed is laid out the moment it arrives: every card's image, text and
/// shadow, for every listing, before the first frame with real content. On a
/// feed of a few dozen rows that is a visible stall, and it grows with the
/// feed instead of staying flat.
///
/// A sliver per rung is the coarse unit — two cards at a time — but it is the
/// unit that has to move. Flattening to one card per sliver would need a
/// different descent to keep the stepped look, and the rungs are what make the
/// layout recognisable.
class CropLadderSliver extends StatelessWidget {
  final List<CropListing> listings;
  final ValueChanged<CropListing> onTap;

  /// Horizontal inset. Vertical spacing is the ladder's own job.
  final double horizontalPadding;

  const CropLadderSliver({
    super.key,
    required this.listings,
    required this.onTap,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverList.builder(
        itemCount: (listings.length / 2).ceil(),
        itemBuilder: (context, index) {
          final first = index * 2;
          final second = first + 1;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              // Per-rung rather than once for the list: a rung's card width
              // depends on the width it was actually given, which is only known
              // here.
              child: LayoutBuilder(
                builder: (context, constraints) => buildLadderRung(
                  left: listings[first],
                  right: second < listings.length ? listings[second] : null,
                  width: constraints.maxWidth,
                  isFirstRung: index == 0,
                  onTap: onTap,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder cards in the ladder's own shape, for the first page load.
///
/// The blocks mirror [CropCard]'s structure — square image, then a bold name
/// line, a lighter farm line and a short rating line — so the feed arrives at
/// the same height it will settle at. A generic centred spinner replaced the
/// whole feed with nothing, which is why every refresh re-collapsed the layout.
///
/// Deliberately static. A shimmer would mean a repeating animation, and an
/// animation that never ends is a permanent `pumpAndSettle` timeout in widget
/// tests, which is a bad trade for a first-load flourish.
class CropCardSkeleton extends StatelessWidget {
  const CropCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.fieldBorder.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: 1,
            child: ColoredBox(color: _kSkeletonFill),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonBar(widthFactor: 0.85, height: 12),
                SizedBox(height: 6),
                _SkeletonBar(widthFactor: 0.6, height: 10),
                SizedBox(height: 8),
                _SkeletonBar(widthFactor: 0.3, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ladder's first [rungCount] rungs, as skeletons.
class CropLadderSkeleton extends StatelessWidget {
  final int rungCount;
  final double horizontalPadding;

  const CropLadderSkeleton({
    super.key,
    this.rungCount = 4,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rungCount; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : _kLadderRowShift,
                      top: i == 0 ? 0 : _kLadderRowGap,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: const CropCardSkeleton()),
                        const SizedBox(width: 8),
                        Expanded(child: const CropCardSkeleton()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const Color _kSkeletonFill = Color(0xFFEFF1F0);

class _SkeletonBar extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _SkeletonBar({required this.widthFactor, required this.height});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: _kSkeletonFill,
          borderRadius: BorderRadius.circular(4),
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

  const CropCardGrid({super.key, required this.listings, required this.onTap});

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
            return CropCard(listing: listing, onTap: () => onTap(listing));
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
