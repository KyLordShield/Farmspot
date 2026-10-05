import 'package:flutter/material.dart';

import '../models/listing_review.dart';
import '../theme.dart';

/// Read-only star row plus the average and review count.
///
/// Renders nothing at all when [summary] has no ratings, which is the rule
/// that matters: an unreviewed listing must not show five empty stars and a
/// "0.0", because that reads as "buyers tried this and hated it". The backend
/// sends `average: null` for exactly that case and this honours it.
///
/// [size] scales the stars for use on a card (14) or a detail header (20).
/// [showCount] adds the "(4)" beside the average; cards show the count because
/// a bare 4.0 is a claim with nothing behind it.
class RatingStars extends StatelessWidget {
  final RatingSummary summary;
  final double size;
  final bool showCount;
  final Color? color;

  const RatingStars({
    super.key,
    required this.summary,
    this.size = 14,
    this.showCount = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!summary.hasRatings) return const SizedBox.shrink();

    final starColor = color ?? AppColors.warningAmber;
    final filled = summary.filledStars;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 1),
            child: Icon(
              i <= filled ? Icons.star : Icons.star_border,
              size: size,
              color: starColor,
            ),
          ),
        const SizedBox(width: 4),
        Text(
          summary.averageLabel,
          style: TextStyle(
            fontSize: size * 0.86,
            fontWeight: FontWeight.w600,
            color: starColor,
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: 3),
          Text(
            '(${summary.count})',
            style: TextStyle(fontSize: size * 0.78, color: Colors.black45),
          ),
        ],
      ],
    );
  }
}

/// Tappable stars for the write-a-review sheet.
///
/// Separate from [RatingStars] on purpose: this one reports taps and is
/// disabled while a save is in flight, which a read-only display must never
/// be.
class StarRatingInput extends StatelessWidget {
  /// Current selection, 1..5, or null when nothing is picked yet.
  final int? value;

  final ValueChanged<int> onChanged;
  final double size;
  final bool enabled;

  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.warningAmber : Colors.black26;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Semantics(
            // Named for screen readers, which would otherwise read five
            // unlabelled icons.
            label: '$star star${star == 1 ? '' : 's'}',
            button: enabled,
            selected: value == star,
            child: GestureDetector(
              onTap: enabled ? () => onChanged(star) : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size * 0.08),
                child: Icon(
                  value != null && star <= value!
                      ? Icons.star
                      : Icons.star_border,
                  size: size,
                  color: color,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The tap target for the stars inside [StarRatingInput].
///
/// 44dp is the smallest reliably tappable size; the visual star is smaller, so
/// this keeps the row at 36 without making it hard to hit.
const double kStarTapTarget = 44;
