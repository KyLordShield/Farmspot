import 'package:flutter/material.dart';

import '../models/listing_review.dart';
import '../screens/all_reviews_screen.dart';
import '../services/review_service.dart';
import '../theme.dart';
import 'farmspot_loader.dart';
import 'rating_stars.dart';
import 'review_card.dart';
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
///
/// The block shows a preview, not the whole list: [previewLimit] best reviews
/// and a "See all" link into [AllReviewsScreen]. Paging used to live here, which
/// meant the buyer had to find and press a button at the bottom of a product
/// page to reach reviews two, three and four — and on a phone that button sat
/// under the fold often enough to be invisible. One link that says how many
/// there are is easier to act on than an afterthought at the end of a scroll.
class ListingReviewsSection extends StatefulWidget {
  final String listingId;
  final String cropName;

  /// Starting summary, usually the one already on the card this screen was
  /// opened from. Shown immediately so the block does not read as empty while
  /// the fetch is in flight, then replaced by the endpoint's own value.
  final RatingSummary initialSummary;

  /// Injectable for tests; the real HTTP service is used when omitted.
  final ReviewsGateway? gateway;

  /// Fires whenever this block learns a new [RatingSummary] — on the first read,
  /// and again after a save, an edit or a delete.
  ///
  /// The product detail screen shows the average beside the crop name from the
  /// listing payload, which is a snapshot taken when the feed was fetched. That
  /// snapshot is stale the moment anyone writes a review: editing a 5★ down to
  /// 4★ left the header reading 5.0 next to a section correctly reading 4.0.
  /// Nothing above this block refetches the listing, so the fresh summary is
  /// reported upward instead of each caller having to go and look.
  final ValueChanged<RatingSummary>? onSummaryChanged;

  const ListingReviewsSection({
    super.key,
    required this.listingId,
    required this.cropName,
    this.initialSummary = const RatingSummary.none(),
    this.gateway,
    this.onSummaryChanged,
  });

  /// Key for the "Write a review" button, used by widget tests.
  static const Key writeButtonKey = Key('reviews-write-button');

  /// Key for the "See all reviews" link, used by widget tests.
  static const Key seeAllKey = Key('reviews-see-all');

  /// How many reviews the preview shows.
  ///
  /// Three, not five: a preview exists to show the shape of what is there, and
  /// five full review cards plus a write button push the rest of the product page
  /// off a phone screen. Three is enough to show the pattern, and anything more
  /// is one tap away.
  static const int previewLimit = 3;

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

  /// Loads the preview: the best [ListingReviewsSection.previewLimit] reviews.
  ///
  /// Asked for `sort=best` rather than newest. On a preview, the newest review
  /// is the least useful of the three on offer — it is most likely to be a bare
  /// star rating, because that is all some buyers bother with — and the one this
  /// row is meant to show is the review that says something. Sorting by rating
  /// and then by whether anyone left words is what the endpoint's `best` does.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _gateway.fetch(
        listingId: widget.listingId,
        perPage: ListingReviewsSection.previewLimit,
        sort: ReviewSort.best,
      );

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
      _reportSummary(result.summary);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Opens the full review list for this listing.
  ///
  /// The write and delete handlers are handed over rather than left behind: a
  /// buyer who scrolls the full list and decides to edit or withdraw their review
  /// should not have to walk back to the product page to do it. The page reloads
  /// on return, so the preview reflects whatever changed.
  Future<void> _seeAll() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AllReviewsScreen(
          listingId: widget.listingId,
          cropName: widget.cropName,
          gateway: widget.gateway,
          onReviewsChanged: _load,
        ),
      ),
    );
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
      _reportSummary(result.summary);
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
      _reportSummary(result.summary);
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

  /// Passes a fresh summary up to the screen, if it is listening.
  ///
  /// Sent unguarded rather than only when the numbers differ. Equality on a
  /// [RatingSummary] would mean comparing the breakdown too, and a caller that
  /// rebuilds a header from what it is handed is cheaper than one that has to
  /// know whether it was told something new.
  void _reportSummary(RatingSummary summary) {
    widget.onSummaryChanged?.call(summary);
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
        // Capped here as well as in the request. per_page=3 is what the endpoint
        // honours, but a server that ignored it would otherwise put five full
        // cards and a write button below the fold on a phone — which is the
        // reason the preview exists rather than the whole list.
        for (final review
            in _page.reviews.take(ListingReviewsSection.previewLimit)) ...[
          ReviewCard(review: review),
          const Divider(height: 20),
        ],
        // Only offered when the preview is genuinely truncated. A listing with
        // three or fewer reviews has nothing behind the link, and a "See all
        // reviews (3)" that opens a three-row list is worse than no link.
        if (_page.total > ListingReviewsSection.previewLimit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ListingReviewsSection.seeAllKey,
              onPressed: _seeAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _page.total == 1
                        ? 'See all 1 review'
                        : 'See all ${_page.total} reviews',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}