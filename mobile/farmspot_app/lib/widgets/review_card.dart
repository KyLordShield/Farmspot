import 'package:flutter/material.dart';

import '../models/listing_review.dart';
import '../theme.dart';
import 'rating_stars.dart';

/// One review, as shown in the product detail preview and in the full list.
///
/// Extracted from the preview so the two cannot drift: the preview and the See
/// all screen list the same reviews, and a change to one that was not made in the
/// other is how a buyer ends up seeing the same review rendered two different
/// ways two taps apart.
///
/// The header row is name on the left and the five stars hard against the right
/// edge. Putting the stars next to the name — which is where they sat originally
/// — made them read as a prefix of the name, so the eye took them for part of a
/// label rather than as a score. Anchored opposite, the stars become a column
/// that can be scanned down the page instead.
///
/// The name is [Flexible] so a long one ellipsizes and the stars keep their
/// width: truncating the rating instead would be the wrong thing to lose.
class ReviewCard extends StatelessWidget {
  final ListingReview review;

  /// Adds a trailing Edit affordance for the caller's own review.
  ///
  /// Only ever passed for `review.isMine`. The See all screen needs it because
  /// the edit button on the product page is out of reach from there.
  final VoidCallback? onEdit;

  const ReviewCard({super.key, required this.review, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          review.reviewer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            // The buyer's own review is coloured and labelled, so
                            // a long list does not leave them guessing which line
                            // is theirs.
                            color: review.isMine
                                ? AppColors.primaryGreen
                                : Colors.black87,
                          ),
                        ),
                      ),
                      if (review.isMine) ...[
                        const SizedBox(width: 6),
                        const Text(
                          'Your review',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (review.createdLabel.isNotEmpty)
                    // Under the name, not under the stars, so the date reads as
                    // belonging to the person rather than to the score.
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        review.createdLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            RatingStars(
              summary: RatingSummary(
                average: review.rating.toDouble(),
                count: 1,
              ),
              size: 14,
            ),
            if (onEdit != null)
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: AppColors.primaryGreen,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                tooltip: 'Edit your review',
              ),
          ],
        ),
        if (review.hasComment) ...[
          const SizedBox(height: 6),
          Text(
            review.comment!,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ],
    );
  }
}