import 'package:flutter/material.dart';

import '../models/listing_review.dart';
import '../services/review_service.dart';
import '../theme.dart';
import 'farmspot_loader.dart';
import 'rating_stars.dart';
import 'review_sheet.dart';

/// The reviews block on the product detail screen.
///
/// Self-contained and injected with a gateway rather than reaching for a
/// service, for the same reason the report sheet is: the screen can then be
/// widget-tested without a server.
///
/// It owns its loading state rather than being handed a prebuilt list, because
/// reviews change as a result of what happens here — a submit, an edit, a
/// delete — and the header average has to move with them.
class ListingReviewsSection extends StatefulWidget {
  final String listingId;
  final String cropName;

  /// Starting summary, usually the one already on the card this screen was
  /// opened from. Shown immediately so the block does not read as empty while
  /// the fetch is in flight, then replaced by the endpoint's own value.
  final RatingSummary initialSummary;

  /// Injectable for tests; the real HTTP service is used when omitted.
  final ReviewsGateway? gateway;

  const ListingReviewsSection({
    super.key,
    required this.listingId,
    required this.cropName,
    this.initialSummary = const RatingSummary.none(),
    this.gateway,
  });

  /// Key for the "Write a review" button, used by widget tests.
  static const Key writeButtonKey = Key('reviews-write-button');

  @override
  State<ListingReviewsSection> createState() => _ListingReviewsSectionState();
}

class _ListingReviewsSectionState extends State<ListingReviewsSection> {
  ReviewsGateway get _gateway => widget.gateway ?? ReviewService.instance;

  ListingReviewsPage _page = const ListingReviewsPage();

  bool _loading = true;

  /// Only ever a short line from the server ("Could not load reviews."). A
  /// failure here must not take the rest of the product page down with it, so
  /// it is shown inline and the block keeps whatever summary it already had.
  String? _error;

  /// Set while a save or delete is in flight, so the controls cannot be
  /// double-tapped into two writes and the sheet shows its spinner.
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _page = ListingReviewsPage(summary: widget.initialSummary);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _gateway.fetch(listingId: widget.listingId);

      if (!mounted) return;

      setState(() {
        _loading = false;
        // Taken from this response rather than merged with what is held: the
        // server resolves can_review and my_review per request, and holding on
        // to a stale value would leave the write button enabled for someone who
        // has since reviewed, or disabled for someone who has not.
        _page = ListingReviewsPage(
          reviews: result.reviews,
          summary: result.summary,
          myReview: result.myReview,
          canReview: result.canReview,
          blockedReason: result.blockedReason,
          currentPage: result.currentPage,
          lastPage: result.lastPage,
          total: result.total,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Fetches the next page and appends it, keeping what is already on screen.
  ///
  /// Separate from [_load] so paging does not blank the list and lose the
  /// buyer's place, and does not reset the summary or the prefill state.
  Future<void> _showMore() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final result = await _gateway.fetch(
        listingId: widget.listingId,
        page: _page.currentPage + 1,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _page = _page
            .withReviews([..._page.reviews, ...result.reviews])
            .copyWith(
              currentPage: result.currentPage,
              lastPage: result.lastPage,
            );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Opens the sheet, then saves and merges whatever comes back.
  ///
  /// Merging rather than refetching is deliberate: the write response carries
  /// the saved row and the recomputed summary, which is exactly what changed,
  /// and refetching would drop a "Show more" the buyer had already tapped.
  Future<void> _write() async {
    final wasEditing = _page.hasMine;

    final draft = await showReviewSheet(
      context: context,
      listingId: widget.listingId,
      cropName: widget.cropName,
      summary: _page.summary,
      existing: _page.myReview,
    );

    if (draft == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await _gateway.save(
        listingId: widget.listingId,
        draft: draft,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        final saved = result.savedReview;
        _page = saved == null
            ? _page.copyWith(summary: result.summary)
            : _page.withSavedReview(saved, result.summary);
      });
      _toast(wasEditing ? 'Review updated.' : 'Review submitted.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Deletes the caller's own review, after confirming.
  Future<void> _delete() async {
    final reviewId = _page.myReview?.id;
    if (reviewId == null || reviewId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your review?'),
        content: const Text(
          'It will be removed from this listing and the average will go back '
          'up or down accordingly. You can write a new one afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.errorTerracotta),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await _gateway.delete(widget.listingId);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _page = _page.withoutReview(reviewId, result.summary);
      });
      _toast('Your review was deleted.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'Reviews',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            if (_page.hasMine)
              // Delete sits in the header next to "Edit your review" rather
              // than on each review row: the seller's own review is the only
              // one a buyer may remove, and "my review" is already flagged.
              TextButton(
                onPressed: _submitting ? null : _delete,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorTerracotta,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Delete', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _buildSummary(),
        const SizedBox(height: 12),
        _buildWriteButton(),
        const SizedBox(height: 16),
        _buildReviews(),
      ],
    );
  }

  Widget _buildSummary() {
    // Nothing rated yet: no stars, no "0.0". The block below already invites the
    // first review, which is the only useful thing to say.
    if (!_page.summary.hasRatings) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        RatingStars(summary: _page.summary, size: 20, showCount: true),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _page.summary.count == 1
                ? 'Based on 1 review'
                : 'Based on ${_page.summary.count} reviews',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildWriteButton() {
    // The write action is only offered on a positive answer. Anything else —
    // blocked, or simply not known yet because the read failed — must not render
    // an enabled button: the sheet would collect a rating that the server then
    // refuses, which looks like the app losing what the user wrote.
    if (!_page.canReview) {
      final reason = _page.blockedReason;

      // A guest gets a sign-in prompt instead of a button that would fail: the
      // sheet would collect a rating and then have nowhere to send it.
      if (reason == 'Sign in to write a review.') {
        return _notice('Sign in to write a review for this crop.');
      }

      // Own listing, removed listing, inactive account: the server's sentence is
      // shown instead of a button, because a disabled button cannot say why.
      if (reason != null) return _notice(reason);

      // Unknown, because the read failed and the error line below already says
      // so. Offering the action here would invite a write that cannot succeed.
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        key: ListingReviewsSection.writeButtonKey,
        onPressed: _submitting ? null : _write,
        icon: Icon(
          _page.hasMine ? Icons.edit_outlined : Icons.star_outline,
          size: 18,
        ),
        label: Text(_page.writeActionLabel),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          side: const BorderSide(color: AppColors.primaryGreen),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
          ),
        ),
      ),
    );
  }

  /// Grey explanatory line, used wherever the rules block an action.
  Widget _notice(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.fieldBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviews() {
    if (_loading && _page.reviews.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: FarmSpotLoader(size: 22)),
      );
    }

    if (_error != null && _page.reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    if (_page.reviews.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'No reviews yet. Be the first to say how this crop was.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final review in _page.reviews) ...[
          _ReviewRow(review: review),
          const Divider(height: 20),
        ],
        if (_page.hasMorePages)
          Center(
            child: TextButton(
              onPressed: _loading ? null : _showMore,
              child: const Text('Show more reviews'),
            ),
          ),
      ],
    );
  }
}

/// One review line: stars, reviewer, when, and the comment if there is one.
class _ReviewRow extends StatelessWidget {
  final ListingReview review;

  const _ReviewRow({required this.review});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RatingStars(
              summary: RatingSummary(
                average: review.rating.toDouble(),
                count: 1,
              ),
              size: 14,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                review.reviewer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  // The buyer's own review is labelled, so a long list does not
                  // leave them wondering which line is theirs.
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
                style: TextStyle(fontSize: 11, color: AppColors.primaryGreen),
              ),
            ],
          ],
        ),
        if (review.createdLabel.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            review.createdLabel,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
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
