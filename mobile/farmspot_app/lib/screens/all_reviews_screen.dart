import 'package:flutter/material.dart';

import '../models/listing_review.dart';
import '../services/review_service.dart';
import '../theme.dart';
import '../widgets/farmspot_loader.dart';
import '../widgets/rating_stars.dart';
import '../widgets/review_card.dart';
import '../widgets/review_sheet.dart';

/// The full review list for one listing, reached from the product detail preview.
///
/// Why a screen and not a longer preview: the endpoint already paginates, and a
/// list that grows a "Show more" button is a list the buyer has to keep
/// discovering. Here the next page arrives on its own, and the controls that
/// matter — sort, star band, comments only — are on screen the whole time.
///
/// State lives here rather than being handed in, because every control changes
/// the query: the list, the counts on the chips and the average in the header are
/// three views of one request, and letting any of them be set independently is
/// how a screen ends up showing "5-star only" above rows that are not 5 stars.
///
/// Three rules the implementation is built around, all of which are the bug the
/// feature is here to prevent:
///   * every sort or filter change resets to page 1, because page 3 of the old
///     query is meaningless against the new one and appending to what is on
///     screen would mix two queries into one list;
///   * a failed page load keeps the rows already on screen rather than clearing
///     them, because a buyer part way down a list would otherwise lose it;
///   * the caller's own review stays reachable under any filter, even one that
///     excludes it, since a review they cannot find is a review they cannot edit
///     or withdraw.
class AllReviewsScreen extends StatefulWidget {
  final String listingId;
  final String cropName;

  /// Injectable for tests; the real HTTP service is used when omitted.
  final ReviewsGateway? gateway;

  /// Called after this screen writes or deletes a review, so the product page
  /// preview behind it can reload rather than showing a stale average.
  final VoidCallback? onReviewsChanged;

  const AllReviewsScreen({
    super.key,
    required this.listingId,
    required this.cropName,
    this.gateway,
    this.onReviewsChanged,
  });

  /// Key for the sort selector, used by widget tests.
  static const Key sortKey = Key('reviews-sort');

  /// Key for the horizontal chip row, so tests can scroll it directly.
  ///
  /// The row is a ListView like the review list below it, which makes "the last
  /// scrollable" ambiguous — naming it keeps a test from scrolling the reviews
  /// when it meant to reach a chip.
  static const Key chipRowKey = Key('reviews-chip-row');

  /// Key for the "With comments" chip.
  static const Key commentsChipKey = Key('reviews-comments-chip');

  /// Key for the star filter chip for [rating].
  static Key ratingChipKey(int rating) => Key('reviews-rating-chip-$rating');

  /// Key for the "Clear filter" button in the empty state.
  static const Key clearFilterKey = Key('reviews-clear-filter');

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  ReviewsGateway get _gateway => widget.gateway ?? ReviewService.instance;

  /// Rows loaded so far, in server order. Appended to, never replaced, except
  /// when the query changes — where starting over is the whole point.
  final List<ListingReview> _reviews = [];

  /// Pages fetched so far, used to dedupe a scroll that fires twice before the
  /// first request answers.
  int _loadedPages = 0;

  RatingSummary _summary = const RatingSummary.none();
  ListingReview? _myReview;
  bool _canReview = false;
  String? _blockedReason;

  ReviewSort _sort = ReviewSort.newest;
  ReviewFilter _filter = const ReviewFilter.all();

  bool _loadingFirstPage = true;
  bool _loadingMore = false;
  String? _error;

  /// The page whose load failed, when the failure is still outstanding.
  ///
  /// Scroll-driven paging fires on every scroll notification, and a failed
  /// request re-renders the footer, which produces another one. Without this,
  /// a page that is failing retried on a loop of its own making, and a server
  /// that is down gets hammered instead of being left alone. Only the button
  /// retries it, or changing the query.
  int? _failedPage;

  /// Set while a save or delete is in flight.
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  /// Last page number seen. One until a response says otherwise.
  int _pageCount = 1;

  /// Whether the server said there is a page after the ones already loaded.
  ///
  /// Driven by the server's own `last_page` rather than by whether the last page
  /// came back full: a page that happens to end short of the page size is still
  /// a page, and stopping there would silently hide the rest.
  bool get _hasMore => _loadedPages < _pageCount;

  /// Whether a load is already in flight, so a second scroll does not queue a
  /// duplicate request for a page that is on its way.
  bool get _busy => _loadingFirstPage || _loadingMore;

  Future<void> _loadFirstPage() async {
    setState(() {
      _loadingFirstPage = true;
      _error = null;
      // A new query has no outstanding failure, even if the previous one did.
      _failedPage = null;
    });

    try {
      final result = await _gateway.fetch(
        listingId: widget.listingId,
        perPage: _pageSize,
        sort: _sort,
        rating: _filter.rating,
        withCommentsOnly: _filter.withCommentsOnly,
      );

      if (!mounted) return;

      setState(() {
        _loadingFirstPage = false;
        // Replaced wholesale rather than merged: these rows belong to the query
        // that was just run, and keeping any from the previous one would leave
        // a 3-star row sitting under a "5 stars only" chip.
        _reviews
          ..clear()
          ..addAll(result.reviews);
        _loadedPages = 1;
        _pageCount = result.lastPage;
        _absorb(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFirstPage = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Appends the next page, keeping what is on screen.
  Future<void> _loadMore() async {
    // _failedPage blocks the automatic path only: the retry button calls this
    // too, and is cleared just below when the retry goes out.
    if (_busy || !_hasMore || _failedPage != null) return;

    final nextPage = _loadedPages + 1;
    setState(() {
      _loadingMore = true;
      // Cleared on the way out so the button can fire this again; put back below
      // if it fails, so a second scroll does not also fire it.
      _failedPage = null;
    });

    try {
      final result = await _gateway.fetch(
        listingId: widget.listingId,
        page: nextPage,
        perPage: _pageSize,
        sort: _sort,
        rating: _filter.rating,
        withCommentsOnly: _filter.withCommentsOnly,
      );

      if (!mounted) return;

      setState(() {
        _loadingMore = false;
        _reviews.addAll(result.reviews);
        _loadedPages = nextPage;
        _pageCount = result.lastPage;
        // Cleared: a recovered page must not leave the error and its retry
        // button sitting under the rows that were fetched after it.
        _error = null;
        // The summary is filter-independent by design, so it does not have to
        // change here — but my_review and can_review are re-resolved per
        // request and are read from this response.
        _absorb(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        // Set, not shown destructively: the rows already loaded stay, and the
        // footer line offers a retry.
        _error = e.toString().replaceFirst('Exception: ', '');
        _failedPage = nextPage;
      });
    }
  }

  /// Retries the page that failed, from the button.
///
/// Separate from [_loadMore] because that one refuses to run while a failure is
/// outstanding, which is what stops the scroll listener looping. The button is
/// the one thing that is allowed to try again, so it clears the block itself.
Future<void> _retryFailedPage() async {
  setState(() {
    _error = null;
    _failedPage = null;
  });
  await _loadMore();
}

void _absorb(ReviewPageResult result) {
    _summary = result.summary;
    _myReview = result.myReview;
    _canReview = result.canReview;
    _blockedReason = result.blockedReason;
  }

  /// Applies a new sort, always from page 1.
  Future<void> _setSort(ReviewSort value) async {
    if (value == _sort) return;
    setState(() => _sort = value);
    await _loadFirstPage();
  }

/// Applies a new star filter, always from page 1.
///
/// Tapping the selected star clears it. The chips are single-select, so the
/// active one has to double as the way back to All: requiring a separate
/// control to undo the last tap means the buyer who taps the wrong star has to
/// find and aim at "All" instead of simply tapping again.
Future<void> _setRating(int? rating) async {
  // Compared against the incoming value rather than the current filter, so the
  // second tap on the same chip is the one that clears it.
  final next = rating == _filter.rating ? null : rating;
  if (next == _filter.rating) return;

  setState(() => _filter = _filter.withRating(next));
  await _loadFirstPage();
}

  /// Toggles "With comments", always from page 1.
  Future<void> _toggleComments() async {
    setState(
      () => _filter = _filter.withComments(!_filter.withCommentsOnly),
    );
    await _loadFirstPage();
  }

  /// Returns to All ratings, comments off.
  Future<void> _clearFilter() async {
    if (!_filter.isActive) return;
    setState(() => _filter = const ReviewFilter.all());
    await _loadFirstPage();
  }

  /// Opens the review sheet for the caller's own review and saves the result.
  Future<void> _editMine() async {
    final existing = _myReview;
    if (existing == null) return;

    final draft = await showReviewSheet(
      context: context,
      listingId: widget.listingId,
      cropName: widget.cropName,
      summary: _summary,
      existing: existing,
    );

    if (draft == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await _gateway.save(
        listingId: widget.listingId,
        draft: draft,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _absorb(result);
      _toast('Review updated.');
      // Reloaded rather than patched in place: an edit can change the rating,
      // which moves the row under a star filter or takes it out of one.
      await _loadFirstPage();
      widget.onReviewsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteMine() async {
    if (_myReview == null) return;

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
      setState(() => _submitting = false);
      _absorb(result);
      _toast('Your review was deleted.');
      await _loadFirstPage();
      widget.onReviewsChanged?.call();
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

  /// Own review, pinned above the rows when the current filter has excluded it.
  ///
  /// A 5-star filter hides a buyer's own 3-star review, which is exactly the
  /// review they need in order to find the edit and delete buttons. Pinned
  /// rather than filtered, and only when it is not already in [reviews], so it
  /// can never appear twice.
  ListingReview? get _pinnedMine {
    final mine = _myReview;
    if (mine == null) return null;
    if (_reviews.any((review) => review.id == mine.id)) return null;
    return mine;
  }

  /// Rows to render, pinned own review first when it is not among them.
  List<ListingReview> get _rows => [
    ?_pinnedMine,
    ..._reviews,
  ];

  /// Whether the loaded rows contain anything the active filter admits.
  ///
  /// The server already applies the filter, so an empty [reviews] is the honest
  /// answer; this only exists to be named where the empty state branches on it.
  bool get _hasMatches => _reviews.isNotEmpty;

  static const int _pageSize = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reviews'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildControls(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Fires on scroll, not on a button press, so the next page
                // arrives before the buyer hits the bottom.
                if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 320) {
                  _loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _rows.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 20),
                itemBuilder: (context, index) {
                  // The extra trailing item is the footer: spinner, retry, or
                  // the end-of-list note.
                  if (index == _rows.length) return _buildFooter();

                  final review = _rows[index];
                  final isPinned = _pinnedMine != null && index == 0;

                  return ReviewCard(
                    review: review,
                    onEdit: review.isMine && _canReview && !_submitting
                        ? _editMine
                        : null,
                    // Marked so the pinned row can be told apart from a row that
                    // simply happened to sort first.
                    key: isPinned ? const Key('reviews-pinned-mine') : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RatingStars(summary: _summary, size: 20, showCount: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // The average and count describe every visible review, not the
                  // filtered set, so they do not move when a chip is tapped.
                  _summary.count == 1
                      ? 'Based on 1 review'
                      : 'Based on ${_summary.count} reviews',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
          if (_myReview != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your review is shown above the list when a filter hides '
                      'it, so you can still edit or delete it.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                  if (_canReview) ...[
                    TextButton(
                      onPressed: _submitting ? null : _editMine,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Edit yours', style: TextStyle(fontSize: 12.5)),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : _deleteMine,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.errorTerracotta,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Delete', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
            )
          else if (_blockedReason != null && _blockedReason != 'Sign in to write a review.')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _blockedReason!,
                style: const TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sort selector, right-aligned above the chips.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ReviewSort>(
                    key: AllReviewsScreen.sortKey,
                    value: _sort,
                    isDense: true,
                    icon: const Icon(Icons.expand_more, size: 18),
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: [
                      for (final option in ReviewSort.values)
                        DropdownMenuItem(
                          value: option,
                          child: Text(option.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _setSort(value);
                    },
                  ),
                ),
              ),
            ),
          ),
          // Horizontal chips: All, then 5 stars down to 1 star with the counts
          // the server sends, then "With comments". Single row, scrolled
          // sideways, because seven chips do not fit a phone width.
          SizedBox(
            key: AllReviewsScreen.chipRowKey,
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildChip(
                  key: const Key('reviews-rating-chip-all'),
                  label: 'All',
                  selected: _filter.rating == null,
                  icon: Icons.star_border,
                  onTap: () => _setRating(null),
                ),
                // 5 down to 1: descending matches how the breakdown is reported
                // and how a buyer thinks about "the good ones".
                for (var stars = 5; stars >= 1; stars--)
                  _buildChip(
                    key: AllReviewsScreen.ratingChipKey(stars),
                    label: _starCountLabel(stars),
                    selected: _filter.rating == stars,
                    icon: Icons.star,
                    // Every band chip shows a filled amber star: they are ratings
                    // the buyer can filter by, not decoration.
                    filledIcon: true,
                    onTap: () => _setRating(stars),
                  ),
                _buildChip(
                  key: AllReviewsScreen.commentsChipKey,
                  label: 'With comments',
                  selected: _filter.withCommentsOnly,
                  icon: Icons.chat_bubble_outline,
                  onTap: _toggleComments,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "5 stars" with the count beside it, e.g. "5 stars (12)".
  ///
  /// The count is omitted rather than shown as zero for a band nobody used,
  /// because "5 stars (0)" on a chip invites a tap that cannot return anything,
  /// while "5 stars" is an honest statement.
  String _starCountLabel(int stars) {
    final count = _summary.countFor(stars);
    if (count == 0) return '$stars stars';
    return '$stars stars ($count)';
  }

  Widget _buildChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData icon = Icons.star_border,
    bool filledIcon = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.primaryGreen : Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            key: key,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? AppColors.primaryGreen : Colors.black12,
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  // Amber on white so the star bands are recognisable, white on
                  // green when selected — the selected chip has to read as
                  // selected without relying on fill alone.
                  color: selected
                      ? Colors.white
                      : filledIcon
                      ? AppColors.warningAmber
                      : Colors.black54,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingFirstPage) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: FarmSpotLoader(size: 22)),
      );
    }

    if (_reviews.isEmpty && _error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _loadFirstPage,
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

    // A filtered list with nothing in it is a different message from a listing
    // nobody has reviewed: one needs the filter cleared, the other needs a
    // review. Saying "no reviews yet" while a 5-star chip is active would be
    // telling the buyer the wrong thing about their own tap.
    // A filter that matches nothing says so, even though the pinned own review
    // may be on screen. Without this, a buyer who reviewed this listing, filtered
    // to a band their own rating is not in, and sees one row at the top with no
    // explanation, is left to guess whether the filter is broken.
    if (_filter.isActive && !_hasMatches) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              'No reviews match this filter.',
              style: TextStyle(fontSize: 13.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: AllReviewsScreen.clearFilterKey,
              onPressed: _clearFilter,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear filter'),
            ),
          ],
        ),
      );
    }

    if (_reviews.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No reviews yet. Be the first to say how this crop was.',
          style: TextStyle(fontSize: 13.5, color: Colors.black54),
        ),
      );
    }

    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: FarmSpotLoader(size: 20)),
      );
    }

    // A page load that failed part way down: the rows above stay, and this
    // offers the retry. Clearing the list here would throw away a page the
    // buyer had already read.
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _retryFailedPage,
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

    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Center(
          child: Text(
            'That is all of them.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),
      );
    }

    return const SizedBox(height: 8);
  }
}