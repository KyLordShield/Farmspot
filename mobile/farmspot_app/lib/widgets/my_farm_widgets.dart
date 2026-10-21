import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/my_farm_listing_page.dart';
import '../theme.dart';

/// One small chip: a dot of colour and a word. Used for every state a farmer
/// row can be in, so "Available Now", "Expired" and "Hidden by admin" cannot
/// end up three different visual languages.
class MyFarmStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;
  final String? explanation;

  const MyFarmStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
    this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              explanation == null ? label : '$label — $explanation',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The farmer's own state on a listing row: availability, expiry countdown,
/// moderation and open reports.
///
/// Kept separate from the row so the mapping is testable on its own — this is
/// the part that has to be right about four different states at once, and it is
/// a lot easier to check as a list of chips than by reading a whole card.
class ListingOwnerChips extends StatelessWidget {
  final ListingOwnerState state;

  const ListingOwnerChips({super.key, required this.state});

  static (String, Color) statusInfo(String status) => switch (status) {
    'AVAILABLE_NOW' => ('Available Now', AppColors.primaryGreen),
    'SOON_TO_HARVEST' => ('Soon to Harvest', AppColors.warningAmber),
    'NOT_AVAILABLE' => ('Not Available', Colors.grey.shade700),
    _ => ('Not Available', Colors.grey.shade700),
  };

  @override
  Widget build(BuildContext context) {
    final listing = state.listing;
    final (statusLabel, statusColor) = statusInfo(listing.status);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // An expired row shows Expired INSTEAD of its underlying status. The
        // expiry command leaves LST_STATUS at NOT_AVAILABLE, so rendering both
        // chips said "Not Available" and "Expired" at once — two answers to the
        // same question, one of which the seller cannot act on.
        if (!state.isExpired)
          MyFarmStatusChip(label: statusLabel, color: statusColor),

        // Expiry is only worth a countdown while there is time left. Past the
        // date the row says Expired, which is the fact the farmer can act on.
        if (state.isExpired)
          const MyFarmStatusChip(
            label: 'Expired',
            color: AppColors.errorTerracotta,
            background: AppColors.errorSoft,
            icon: Icons.event_busy_outlined,
          )
        else if (state.expiryLabel != null)
          MyFarmStatusChip(
            label: state.expiryLabel!,
            color: AppColors.infoSage,
            background: AppColors.infoSoft,
            icon: Icons.schedule,
          ),

        if (state.isTakenDown)
          MyFarmStatusChip(
            label: 'Taken down',
            color: AppColors.errorTerracotta,
            background: AppColors.errorSoft,
            icon: Icons.gpp_bad_outlined,
            // The admin's reason, verbatim, so the farmer knows what they are
            // answering before they request a re-evaluation. A takedown without
            // a reason should not happen (the admin form requires one), but the
            // fallback keeps the chip honest rather than printing "null".
            explanation: (state.takedownReason?.trim().isNotEmpty ?? false)
                ? 'Reason: ${state.takedownReason}'
                : 'An admin took this listing down. You can request a review.',
          )
        else if (state.hiddenByAdmin)
          const MyFarmStatusChip(
            label: 'Hidden by admin',
            color: AppColors.errorTerracotta,
            background: AppColors.errorSoft,
            icon: Icons.visibility_off_outlined,
            // One line, no details: the farmer learns what happened and who to
            // ask, and nothing about the moderation process behind it.
            explanation:
                'Buyers cannot see this listing. Contact the '
                'Association Secretary.',
          ),

        if (state.hasPendingAppeal)
          const MyFarmStatusChip(
            label: 'Re-evaluation in review',
            color: AppColors.infoSage,
            background: AppColors.infoSoft,
            icon: Icons.hourglass_top,
            explanation:
                'Your request is with the Association. You will be told the '
                'outcome.',
          ),

        if (state.underReview)
          const MyFarmStatusChip(
            label: 'Under review',
            color: AppColors.warningAmber,
            background: AppColors.warningSoft,
            icon: Icons.fact_check_outlined,
            // Deliberately says nothing about the report itself. A seller who
            // could see who reported them could retaliate, and a report is an
            // accusation until the Association has looked at it.
            explanation:
                'A report on this listing is being reviewed by the Association.',
          ),
      ],
    );
  }
}

/// The farmer's rating on one listing: "★ 4.5 (12)", or "No reviews yet".
///
/// Different from the buyer-facing CompactRatingLabel in one deliberate way:
/// an unreviewed crop says so. Buyers get silence, because "No reviews yet" on
/// every card of a new marketplace is noise, but a farmer asking "how are my
/// crops doing?" needs to tell the difference between no reviews and a hidden
/// zero.
class OwnerRatingLabel extends StatelessWidget {
  final Listing listing;
  final VoidCallback? onTap;

  const OwnerRatingLabel({super.key, required this.listing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ratings = listing.ratings;
    final average = ratings.average;

    // Both halves of hasRatings are checked, not just the flag: a payload with a
    // count but a null average would otherwise print "null".
    if (!ratings.hasRatings || average == null) {
      return _tappable(
        child: Text(
          'No reviews yet',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.45),
            decoration: onTap == null ? null : TextDecoration.underline,
            decorationColor: Colors.black26,
          ),
        ),
      );
    }

    return _tappable(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: AppColors.warningAmber),
          const SizedBox(width: 3),
          Text(
            average.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            ' (${ratings.count})',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// Wraps only when there is somewhere to go. A GestureDetector with a null
  /// handler still absorbs taps, which would make the rating label swallow the
  /// row's own tap target.
  Widget _tappable({required Widget child}) {
    if (onTap == null) return child;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

/// Small, lazily loaded list thumbnail.
///
/// Two deliberate choices:
///   * cacheWidth/cacheHeight ask the decoder for a thumbnail-sized bitmap.
///     A 68px box decoded from a 4000px photo is the single biggest source of
///     memory churn in a scrolling list, and every row here is a photo.
///   * a Cloudinary URL gets a transformation segment (w_300, q_auto, f_auto)
///     so the bytes that cross the network are already small. A non-Cloudinary
///     URL is passed through untouched — rewriting an arbitrary host's URL
///     would break it, and the decoder hint above already covers that case.
///
/// No new package: cached_network_image is not in pubspec.yaml, so this is
/// Image.network with the hints the framework already provides.
class ListingThumbnail extends StatelessWidget {
  final String? url;
  final double size;

  const ListingThumbnail({super.key, this.url, this.size = 68});

  /// Width to request from the image host. Matches the physical width of the
  /// box on a 3x phone, rounded up, so the row is still sharp.
  static const int _decodeWidth = 300;

  /// The URL actually requested, after the Cloudinary transformation.
  ///
  /// Exposed for tests: this rewrite is the difference between pulling a 4000px
  /// photo and pulling a 300px one, and a rule about URLs is worth a test that
  /// does not have to decode an image to check it.
  static String? resizedForTest(String? raw) => _resized(raw);

  static String? _resized(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.contains('/upload/')) return raw;
    // Already transformed: leave it alone rather than stacking segments.
    if (raw.contains('/w_')) return raw;
    final marker = raw.indexOf('/upload/') + '/upload/'.length;
    return '${raw.substring(0, marker)}w_$_decodeWidth,q_auto,f_auto/'
        '${raw.substring(marker)}';
  }

  @override
  Widget build(BuildContext context) {
    final resized = _resized(url);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: resized == null
            ? _fallback()
            : Image.network(
                resized,
                fit: BoxFit.cover,
                cacheWidth: _decodeWidth,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(color: AppColors.successSoft);
                },
                errorBuilder: (context, error, stack) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: AppColors.successSoft,
      child: const Icon(Icons.eco, color: AppColors.primaryGreen, size: 30),
    );
  }
}

/// One My Farm listing row: thumbnail, crop name, every chip that applies, the
/// farmer's rating, and the actions that were already here.
///
/// The existing CropListTile is left untouched for its other callers; this is a
/// new widget because the chips, the "No reviews yet" state and the read-only
/// reviews entry point are owner-only concerns that would otherwise make the
/// shared tile grow a dozen nullable flags.
class MyFarmListingRow extends StatelessWidget {
  final Listing listing;
  final ListingOwnerState state;
  final bool updating;

  final VoidCallback? onTap;
  final VoidCallback? onStatusTap;
  final VoidCallback? onRenewTap;
  final VoidCallback? onReviewsTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onDeleteTap;

  /// Opens the read-only panel describing the takedown — reason, date and farm —
  /// with the appeal action at the bottom. A taken-down row offers nothing else,
  /// so this replaces every other action rather than sitting alongside them.
  final VoidCallback? onViewTakedownTap;

  const MyFarmListingRow({
    super.key,
    required this.listing,
    required this.state,
    this.updating = false,
    this.onTap,
    this.onStatusTap,
    this.onRenewTap,
    this.onReviewsTap,
    this.onEditTap,
    this.onDeleteTap,
    this.onViewTakedownTap,
  });

  String get _label => listing.cropIcon ?? listing.categoryName ?? 'Crop';

  @override
  Widget build(BuildContext context) {
    // A taken-down row is a different card, not the normal card with pieces
    // missing. Buyers cannot see it, the farmer cannot change or renew it, and
    // the only thing left to do is read why and ask for it back — so every other
    // action, and the more menu, is dropped rather than shown dead.
    final takenDown = state.isTakenDown;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // A moderated row is outlined rather than greyed out: the farmer still
          // has to be able to read it, and dimming the whole card makes it look
          // disabled when the real problem is that buyers cannot see it.
          color: (takenDown || state.hiddenByAdmin)
              ? AppColors.errorTerracotta.withValues(alpha: 0.35)
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListingThumbnail(url: listing.image),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The rating is not tappable on a taken-down row: its entry
                  // point is the Reviews action, and that action is gone.
                  OwnerRatingLabel(
                    listing: listing,
                    onTap: takenDown ? null : onReviewsTap,
                  ),
                  const SizedBox(height: 8),
                  if (takenDown)
                    _buildTakedownWarning()
                  else ...[
                    ListingOwnerChips(state: state),
                    const SizedBox(height: 8),
                    _buildActions(),
                  ],
                ],
              ),
            ),
            if (!takenDown) ...[const SizedBox(width: 4), _buildMenu()],
          ],
        ),
      ),
    );
  }

  /// The only body a taken-down row shows: the warning and a way to open the
  /// details panel. The reason itself lives in that panel, not here, so the card
  /// stays a card rather than a paragraph.
  Widget _buildTakedownWarning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.errorSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.gpp_bad_outlined,
                size: 16,
                color: AppColors.errorTerracotta,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This listing was taken down by an admin.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AppColors.errorTerracotta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (onViewTakedownTap != null)
          GestureDetector(
            onTap: onViewTakedownTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.errorTerracotta.withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: AppColors.errorTerracotta,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'View details',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.errorTerracotta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The existing status picker entry point, plus Renew once the window ends.
  ///
  /// Renew is driven by the expiry date rather than LST_STATUS, so it stays
  /// available after listings:expire has already turned the row into
  /// NOT_AVAILABLE. The renewal sheet itself asks for a fresh camera photo and
  /// confirms whether the crop is available now or still soon.
  Widget _buildActions() {
    if (updating) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onStatusTap != null)
          GestureDetector(
            onTap: onStatusTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.edit_outlined,
                    size: 12,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Change status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (state.canRenew && onRenewTap != null)
          GestureDetector(
            onTap: onRenewTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Renew',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (onReviewsTap != null)
          GestureDetector(
            onTap: onReviewsTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: const Text(
                'Reviews',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenu() {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.black45),
      onSelected: (value) {
        if (value == 'edit') {
          onEditTap?.call();
        } else if (value == 'delete') {
          onDeleteTap?.call();
        }
      },
      itemBuilder: (context) => [
        if (onEditTap != null)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
        if (onDeleteTap != null)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The All / Active / Expired / Under review / Hidden filter row.
///
/// A horizontal ListView because five chips with counts do not fit a 360px
/// screen, and a Wrap would push the list down every time a count grew a digit.
class MyFarmFilterRow extends StatelessWidget {
  final MyFarmStatusFilter active;
  final MyFarmSummary summary;
  final ValueChanged<MyFarmStatusFilter> onChanged;

  const MyFarmFilterRow({
    super.key,
    required this.active,
    required this.summary,
    required this.onChanged,
  });

  /// Key for one filter chip, so a test can find it by identity rather than by
  /// its label text — "Hidden by admin" is also the chip's own text, and matching
  /// on text would break the moment the wording changes.
  static Key chipKey(MyFarmStatusFilter filter) =>
      Key('myfarm-filter-${filter.wire}');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MyFarmStatusFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = MyFarmStatusFilter.values[i];
          final selected = filter == active;
          final count = summary.countFor(filter);

          return GestureDetector(
            key: chipKey(filter),
            onTap: () => onChanged(filter),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? AppColors.primaryGreen : Colors.black12,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The farm's own numbers at the top of My Farm: overall average, how many
/// reviews, and how many listings.
///
/// The average is the backend's weighted one — every review row counted once —
/// so it cannot drift from what the per-listing numbers add up to.
class MyFarmSummaryCard extends StatelessWidget {
  final MyFarmSummary summary;

  const MyFarmSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final average = summary.ratingAverage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.searchBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your ratings',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedGreen,
                  ),
                ),
                const SizedBox(height: 6),
                // Nothing at all when nothing has been reviewed: a row of
                // "0.0" next to an empty star is a score nobody gave.
                if (average == null)
                  const Text(
                    'No reviews yet',
                    style: TextStyle(fontSize: 15, color: Colors.black45),
                  )
                else ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        size: 18,
                        color: AppColors.warningAmber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        average.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.reviewCount == 1
                        ? 'Based on 1 review'
                        : 'Based on ${summary.reviewCount} reviews',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.black12),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Listings',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedGreen,
                ),
              ),
              const SizedBox(height: 6),
              // The farm's total, not the number of rows on screen: a page of ten
              // out of forty listings must not report ten.
              Text(
                '${summary.totalListings}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Read-only panel for a taken-down listing: what was said, when, and where,
/// with the one action that remains — ask for it back.
///
/// The reason lives here rather than in the row so the card can stay a card.
/// Pops `true` when the farmer taps Request appeal; the caller then opens the
/// explanation dialog. Popping `false`/null means they just closed it.
class TakedownDetailsSheet extends StatelessWidget {
  final Listing listing;
  final ListingOwnerState state;

  const TakedownDetailsSheet({
    super.key,
    required this.listing,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final reason = (state.takedownReason ?? '').trim();
    final crop = (listing.cropIcon ?? '').trim();
    final title = crop.isNotEmpty
        ? crop
        : (listing.categoryName ?? 'This listing');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.gpp_bad_outlined,
                      color: AppColors.errorTerracotta,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Listing taken down',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                _section(
                  'Reason from the Association',
                  reason.isEmpty ? 'No reason was recorded.' : reason,
                  highlight: true,
                ),
                const SizedBox(height: 14),
                _section(
                  'Taken down on',
                  _formatTakedownDate(listing.takedownAt),
                ),
                const SizedBox(height: 14),
                _section(
                  'Farm',
                  (listing.farmName ?? '').trim().isEmpty
                      ? '—'
                      : listing.farmName!.trim(),
                ),
                if (state.hasPendingAppeal) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.hourglass_top,
                          size: 16,
                          color: AppColors.infoSage,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your re-evaluation request is with the Association. '
                            'You will be told the outcome.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppColors.infoSage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (state.canRequestReEvaluation)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Request appeal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.errorTerracotta,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                else if (!state.hasPendingAppeal)
                  const Text(
                    'This listing can no longer be appealed.',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedGreen,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: highlight ? AppColors.errorTerracotta : Colors.black87,
            fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// The explanation a farmer files with a re-evaluation request.
///
/// A StatefulWidget so the TextEditingController is owned by the dialog and
/// disposed when the dialog's element finally unmounts. Creating the controller
/// in the caller and disposing it as soon as showDialog's future completes
/// tears it down while the route is still animating out, which the TextField is
/// still reading — the cause of the "_dependents.isEmpty" assertion crash.
///
/// Pops the typed reason, or null when cancelled.
class ReEvaluationDialog extends StatefulWidget {
  final String? takedownReason;

  const ReEvaluationDialog({super.key, this.takedownReason});

  @override
  State<ReEvaluationDialog> createState() => _ReEvaluationDialogState();
}

class _ReEvaluationDialogState extends State<ReEvaluationDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = (widget.takedownReason ?? '').trim();

    return AlertDialog(
      title: const Text('Request re-evaluation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason.isNotEmpty) ...[
            const Text(
              'Reason given for the takedown:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              reason,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 14),
          ],
          const Text(
            'Tell the Association why this listing should be restored.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'Your explanation',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Send request'),
        ),
      ],
    );
  }
}

/// "Oct 17, 2026 at 3:42 PM", or "Unknown" when the timestamp is missing or
/// unparseable. No intl package, so the month is looked up by hand.
String _formatTakedownDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Unknown';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour24 = dt.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = hour24 < 12 ? 'AM' : 'PM';

  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour12:$minute $period';
}
