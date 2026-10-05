import 'package:flutter/material.dart';

import '../models/listing_review.dart';
import '../theme.dart';
import 'rating_stars.dart';

/// The write/edit review sheet.
///
/// A bottom sheet rather than a screen, because writing a review is one short
/// action: five stars and an optional line. It is handed the reviewer's own
/// existing review and opens filled in, so "edit" and "write" are the same
/// sheet with different starting state and different button labels — there is
/// no second form to keep in sync.
///
/// Everything is read-only apart from the stars and the comment box; a seller
/// has nothing to edit here, so the caller simply does not open it.
Future<ReviewDraft?> showReviewSheet({
  required BuildContext context,
  required String listingId,
  required String cropName,
  RatingSummary summary = const RatingSummary.none(),
  ListingReview? existing,
  bool submitting = false,
}) {
  return showModalBottomSheet<ReviewDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewSheet(
      listingId: listingId,
      cropName: cropName,
      summary: summary,
      existing: existing,
      submitting: submitting,
    ),
  );
}

class _ReviewSheet extends StatefulWidget {
  final String listingId;
  final String cropName;
  final RatingSummary summary;
  final ListingReview? existing;
  final bool submitting;

  const _ReviewSheet({
    required this.listingId,
    required this.cropName,
    required this.summary,
    this.existing,
    this.submitting = false,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final TextEditingController _comment = TextEditingController(
    text: widget.existing?.comment ?? '',
  );

  /// Null until a star is tapped. Deliberately not defaulted to 5 or to the
  /// current average: pre-picking a score submits a rating the user never gave.
  late int? _rating = widget.existing?.rating;

  /// The same cap the server enforces, checked here only to disable the button
  /// early. The server still validates, because a client-side limit is a
  /// convenience and not a control.
  static const int maxCommentLength = 300;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  bool get _canSubmit => _rating != null && !widget.submitting;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(
      context,
    ).pop(ReviewDraft(rating: _rating!, comment: _comment.text));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return Padding(
      // Lifts the sheet above the keyboard so the comment box stays visible
      // while typing.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                editing ? 'Edit your review' : 'Write a review',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.cropName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              // The average so far, so a buyer rates against what others think
              // rather than blind. Hidden when nothing is rated yet.
              if (widget.summary.hasRatings) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    RatingStars(
                      summary: widget.summary,
                      size: 15,
                      showCount: true,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'so far',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              // "How would you rate it?" — centred so the five stars read as a
              // scale rather than as a control to the left of the field.
              Center(
                child: Column(
                  children: [
                    StarRatingInput(
                      value: _rating,
                      onChanged: (value) => setState(() => _rating = value),
                      enabled: !widget.submitting,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _ratingLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Comment (optional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                enabled: !widget.submitting,
                maxLines: 4,
                minLines: 3,
                maxLength: maxCommentLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'How was the quality, the price, the pickup?',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.fieldBackground,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.fieldBorder),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Shown only once the limit is in reach, so a short comment is not
              // decorated with a warning that does not apply yet.
              if (_comment.text.trim().length > maxCommentLength - 40)
                Text(
                  '${_comment.text.trim().length}/$maxCommentLength',
                  style: TextStyle(
                    fontSize: 11,
                    color: _comment.text.trim().length > maxCommentLength
                        ? AppColors.errorTerracotta
                        : Colors.black45,
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const Key('review-sheet-submit'),
                  // Disabled, not hidden, when no star is picked: the button is
                  // where a buyer looks for it, and it explains itself through
                  // the star row above.
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: widget.submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(editing ? 'Update review' : 'Submit review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Plain-language meaning of the current selection, so the stars are not the
  /// only signal that the choice registered.
  String get _ratingLabel => switch (_rating) {
    null => 'Tap a star to rate',
    1 => 'Poor',
    2 => 'Not great',
    3 => 'Okay',
    4 => 'Good',
    _ => 'Excellent',
  };
}
