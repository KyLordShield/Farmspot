import 'dart:async';

import 'package:farmspot_app/models/listing_review.dart';
import 'package:farmspot_app/screens/all_reviews_screen.dart';
import 'package:farmspot_app/services/review_service.dart';
import 'package:farmspot_app/widgets/rating_stars.dart';
import 'package:farmspot_app/widgets/review_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------------ fixtures

/// Recording stand-in for the review endpoints.
///
/// Answers by page and records the full scope of every request, because the
/// three things this screen can be wrong about are all about which query was
/// sent: a filter that did not reach the server, a sort that leaked across a
/// filter change, and a page reset that did not happen.
class RecordingGateway implements ReviewsGateway {
  /// Keyed by page number, as the endpoint's responses are.
  final Map<int, ReviewPageResult> pages = {};

  final List<({int page, int? rating, bool withComments, ReviewSort sort})>
  requests = [];

  /// Set to make the matching page throw instead of answering.
  String? fetchError;

  /// Set to hold page 1 open, so a test can act before it lands.
  Completer<ReviewPageResult>? holdFirstPage;

  @override
  Future<ReviewPageResult> fetch({
    required String listingId,
    int page = 1,
    int perPage = 5,
    ReviewSort sort = ReviewSort.newest,
    int? rating,
    bool withCommentsOnly = false,
  }) async {
    requests.add((
      page: page,
      rating: rating,
      withComments: withCommentsOnly,
      sort: sort,
    ));

    if (page == 1) {
      final hold = holdFirstPage;
      if (hold != null) return hold.future;
    }

    if (fetchError != null) throw Exception(fetchError!);
    return pages[page] ??
        const ReviewPageResult(reviews: [], summary: RatingSummary.none());
  }

  @override
  Future<ReviewPageResult> save({
    required String listingId,
    required ReviewDraft draft,
  }) async {
    throw UnimplementedError('No write in these tests.');
  }

  @override
  Future<ReviewPageResult> delete(String listingId) async {
    throw UnimplementedError('No delete in these tests.');
  }
}

ListingReview aReview({
  String id = 'LRV001',
  int rating = 5,
  String? comment = 'Very fresh, big crates.',
  String reviewer = 'Maria S.',
  bool isMine = false,
}) {
  return ListingReview(
    id: id,
    listingId: 'LST0001',
    rating: rating,
    comment: comment,
    reviewer: reviewer,
    createdAt: '2026-10-01T08:30:00Z',
    updatedAt: '2026-10-01T08:30:00Z',
    isMine: isMine,
  );
}

/// Tall enough that ten rows overflow a phone, so the scroll trigger can fire.
ReviewPageResult aPage({
  List<ListingReview> reviews = const [],
  RatingSummary summary = const RatingSummary(average: 4.3, count: 9),
  ListingReview? myReview,
  bool canReview = true,
  int currentPage = 1,
  int lastPage = 1,
  int total = 9,
}) {
  return ReviewPageResult(
    reviews: reviews,
    summary: summary,
    myReview: myReview,
    canReview: canReview,
    currentPage: currentPage,
    lastPage: lastPage,
    total: total,
  );
}

void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// A phone with a shorter window, so ten rows of review actually overflow and
/// the scroll-driven paging can be reached by dragging.
void _useShortPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 520);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Drags to the end of the list.
///
/// A fling can stop short of the bottom on a long list and never reach the
/// threshold; a drag long enough to pin to the end always will, and the listener
/// fires from the scroll position, not from the gesture kind.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
  await tester.pumpAndSettle();
}

/// Drags back to the top of the list.
Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, 3000));
  await tester.pumpAndSettle();
}

/// Scrolls the chip row sideways until [finder] is on screen, then taps it.
///
/// The seven chips do not fit a phone width by design, so a test that wants the
/// last one has to do what a buyer does: swipe them into view.
///
/// dragUntilVisible rather than scrollUntilVisible, because the chips are lazily
/// built — the ones past the edge do not exist until the row is scrolled — and
/// because scrollUntilVisible works out its drag direction by looking for an
/// ancestor Scrollable. The chip row's own Scrollable is a descendant, not an
/// ancestor, so it cannot tell the row is horizontal and drags it vertically
/// until it runs out of attempts.
Future<void> _tapChip(WidgetTester tester, Finder finder) async {
  await _revealChip(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into the chip row without touching it.
Future<void> _revealChip(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      finder,
      find.byKey(AllReviewsScreen.chipRowKey),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
  }

  // dragUntilVisible stops as soon as the target is *built*, which happens while
  // it is still only half on screen — the right-hand edge of the chip row. A tap
  // aimed at its centre then lands on whatever is under that point, which is how
  // "select 3 stars" ends up clearing the selection instead. Pulled fully into
  // view before anything is tapped.
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  RecordingGateway gateway, {
  VoidCallback? onReviewsChanged,
}) async {
  _usePhone(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: AllReviewsScreen(
        listingId: 'LST0001',
        cropName: 'Carrots',
        gateway: gateway,
        onReviewsChanged: onReviewsChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<ListingReview> _rows(int count, {int startAt = 0}) => [
  for (var i = startAt; i < startAt + count; i++)
    aReview(id: 'R$i', reviewer: 'Reviewer $i', comment: 'Comment number $i.'),
];

// --------------------------------------------------------------------- tests

void main() {
  group('AllReviewsScreen reading', () {
    testWidgets('lists the first page and asks for it unfiltered', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(3));

      await _pumpScreen(tester, gateway);

      expect(find.byType(ReviewCard), findsNWidgets(3));
      expect(gateway.requests, hasLength(1));
      // Untouched screen means no narrowing parameters at all, so the first
      // request is the same one the endpoint always answered.
      expect(gateway.requests.single.sort, ReviewSort.newest);
      expect(gateway.requests.single.rating, isNull);
      expect(gateway.requests.single.withComments, isFalse);
    });

    testWidgets('shows the running average and count from the summary', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(
          reviews: _rows(2),
          summary: const RatingSummary(average: 4.5, count: 12),
        );

      await _pumpScreen(tester, gateway);

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('Based on 12 reviews'), findsOneWidget);
    });

    testWidgets('a first-page failure offers a retry and keeps the error', (
      tester,
    ) async {
      final gateway = RecordingGateway()..fetchError = 'Could not reach the server.';

      await _pumpScreen(tester, gateway);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      gateway
        ..fetchError = null
        ..pages[1] = aPage(reviews: _rows(2));

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewCard), findsNWidgets(2));
      expect(find.text('Could not reach the server.'), findsNothing);
    });
  });

  group('AllReviewsScreen filters', () {
testWidgets('a star chip sends the rating and resets to page one', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(10), lastPage: 2)
        ..pages[2] = aPage(reviews: _rows(4), currentPage: 2, lastPage: 2);

      await _pumpScreen(tester, gateway);
      await _scrollToEnd(tester);

      // Scrolled onto page two first, so "reset to page one" is actually
      // exercised rather than a no-op that happens to pass.
      expect(gateway.requests.last.page, 2);

      await _tapChip(tester, find.byKey(AllReviewsScreen.ratingChipKey(4)));

      final last = gateway.requests.last;
      expect(last.rating, 4);
      expect(last.page, 1);
      // Page two of the *unfiltered* query must not be kept: it is a different
      // set of reviews from page one of the filtered query.
      expect(gateway.requests.map((r) => r.page), [1, 2, 1]);
    });

    testWidgets('tapping the active star clears it back to All', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(2));

      await _pumpScreen(tester, gateway);

      await _tapChip(tester, find.byKey(AllReviewsScreen.ratingChipKey(5)));
      expect(gateway.requests.last.rating, 5);

      // Tapping the same chip again is the undo, so a buyer who taps the wrong
      // band does not have to aim for "All".
      await _tapChip(tester, find.byKey(AllReviewsScreen.ratingChipKey(5)));
      expect(gateway.requests.last.rating, isNull);
    });

    testWidgets('With comments combines with the selected star', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(2));

      await _pumpScreen(tester, gateway);

      await _tapChip(tester, find.byKey(AllReviewsScreen.ratingChipKey(3)));
      await _tapChip(tester, find.byKey(AllReviewsScreen.commentsChipKey));

      final last = gateway.requests.last;
      // Both at once: "3 stars" alone would drop the commented four-star reviews
      // the buyer is asking to read.
      expect(last.rating, 3);
      expect(last.withComments, isTrue);
    });

    testWidgets('a filter matching nothing offers Clear filter, which works', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(2));

      await _pumpScreen(tester, gateway);

      // Page one answers empty, as a filter that matches nothing would.
      gateway.pages[1] = aPage(
        reviews: const [],
        summary: const RatingSummary(average: 4.3, count: 9),
      );
      await _tapChip(tester, find.byKey(AllReviewsScreen.ratingChipKey(1)));

      expect(find.text('No reviews match this filter.'), findsOneWidget);
      // Not "no reviews yet": the listing has nine, the filter has none.
      expect(find.textContaining('No reviews yet'), findsNothing);

      gateway.pages[1] = aPage(reviews: _rows(2));
      await tester.tap(find.byKey(AllReviewsScreen.clearFilterKey));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewCard), findsNWidgets(2));
      expect(gateway.requests.last.rating, isNull);
    });

    testWidgets('an unfiltered listing with no reviews says so plainly', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(
          reviews: const [],
          summary: const RatingSummary.none(),
          total: 0,
        );

      await _pumpScreen(tester, gateway);

      expect(find.textContaining('No reviews yet'), findsOneWidget);
      // Nothing to clear, so no button pretending otherwise.
      expect(find.byKey(AllReviewsScreen.clearFilterKey), findsNothing);
    });

    testWidgets('chips carry the server breakdown counts', (tester) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(
          reviews: _rows(2),
          summary: const RatingSummary(
            average: 4.3,
            count: 9,
            ratingBreakdown: {5: 4, 4: 3, 3: 2},
          ),
        );

      await _pumpScreen(tester, gateway);

// 5 stars and 4 stars have reviews; 3, 2 and 1 do not.
      expect(find.text('5 stars (4)'), findsOneWidget);
      expect(find.text('4 stars (3)'), findsOneWidget);
      // Brought into view, not tapped: this is a question about the labels.
      await _revealChip(tester, find.text('3 stars (2)'));
      expect(find.text('3 stars (2)'), findsOneWidget);
      // A band nobody used prints without a "(0)", which would invite a tap
      // that cannot return anything.
      await _revealChip(tester, find.text('2 stars'));
      expect(find.text('2 stars (0)'), findsNothing);
    });

    testWidgets('the header average ignores the active filter', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(
          reviews: _rows(2),
          summary: const RatingSummary(
            average: 4.3,
            count: 9,
            ratingBreakdown: {5: 6},
          ),
        );

      await _pumpScreen(tester, gateway);

      await tester.tap(find.byKey(AllReviewsScreen.ratingChipKey(5)));
      await tester.pumpAndSettle();

      // Filtered to five stars, but the average and count still describe the
      // listing: a buyer comparing "4.3 from 9" against the card they came from
      // must not be told it is 5.0 from 6.
      expect(find.text('4.3'), findsOneWidget);
      expect(find.text('Based on 9 reviews'), findsOneWidget);
    });
  });

  group('AllReviewsScreen sorting', () {
    testWidgets('the selector sends the chosen sort', (tester) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(2));

      await _pumpScreen(tester, gateway);

      await tester.tap(find.byKey(AllReviewsScreen.sortKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lowest').last);
      await tester.pumpAndSettle();

      expect(gateway.requests.last.sort, ReviewSort.lowest);
      expect(gateway.requests.last.page, 1);
    });

    testWidgets('every sort option is offered', (tester) async {
      final gateway = RecordingGateway()..pages[1] = aPage(reviews: _rows(1));

      await _pumpScreen(tester, gateway);

      await tester.tap(find.byKey(AllReviewsScreen.sortKey));
      await tester.pumpAndSettle();

      for (final label in ['Best', 'Newest', 'Highest', 'Lowest']) {
        expect(find.text(label), findsWidgets);
      }
    });
  });

group('AllReviewsScreen paging', () {
    testWidgets('scrolling appends the next page without dropping rows', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(10), lastPage: 2)
        ..pages[2] = aPage(reviews: _rows(10, startAt: 10), currentPage: 2, lastPage: 2);

      _useShortPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AllReviewsScreen(
            listingId: 'LST0001',
            cropName: 'Carrots',
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollToEnd(tester);

      // Page two arrived...
      expect(gateway.requests.last.page, 2);
      expect(find.text('Reviewer 10'), findsOneWidget);
      // ...and page one is still underneath it. Checked after scrolling back,
      // because a lazy list disposes rows that scroll off screen: their absence
      // from the tree here would mean "off screen", not "dropped".
      await _scrollToTop(tester);
      expect(find.text('Reviewer 0'), findsOneWidget);
      // And it does not keep going past the last page.
      expect(gateway.requests.where((r) => r.page == 2), hasLength(1));
    });

    testWidgets('the last page says so instead of spinning forever', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(10), lastPage: 1);

      _useShortPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AllReviewsScreen(
            listingId: 'LST0001',
            cropName: 'Carrots',
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollToEnd(tester);

      expect(find.text('That is all of them.'), findsOneWidget);
    });

    testWidgets('a later page failure keeps the rows and offers a retry', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(10), lastPage: 2)
        ..pages[2] = aPage(reviews: _rows(6), currentPage: 2, lastPage: 2);

      _useShortPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AllReviewsScreen(
            listingId: 'LST0001',
            cropName: 'Carrots',
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Page two fails: the buyer must not lose the list to see a message.
      gateway.fetchError = 'Could not reach the server.';
      await _scrollToEnd(tester);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Reviewer 9'), findsOneWidget);
      // Asked for once. The footer re-rendering produces more scroll
      // notifications, and a failure that re-fired on each of them would retry a
      // broken page forever without the buyer doing anything.
      expect(gateway.requests.map((r) => r.page), [1, 2]);

      gateway
        ..fetchError = null
        ..pages[2] = aPage(
          reviews: _rows(10, startAt: 10),
          currentPage: 2,
          lastPage: 2,
        );

      // Tapped where it is, without scrolling in between: scrolling back to the
      // top and down again would re-trigger the load itself, which would make
      // this pass whether or not the button did anything.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(gateway.requests.map((r) => r.page), [1, 2, 2]);
      // The new rows land below the current offset, so they are only in the tree
      // once the list is scrolled to its new end.
      await _scrollToEnd(tester);
      expect(find.text('Reviewer 19'), findsOneWidget);
      // And the recovered page takes its error and retry button with it.
      expect(find.text('Could not reach the server.'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('AllReviewsScreen own review', () {
    testWidgets('is pinned above the list when the filter excludes it', (
      tester,
    ) async {
      final mine = aReview(id: 'MINE', rating: 2, reviewer: 'Me', isMine: true);

      final gateway = RecordingGateway()
        ..pages[1] = aPage(
          // Filtered to five stars, so the two-star own review is not in the
          // rows the server sent.
          reviews: [aReview(id: 'A', rating: 5)],
          myReview: mine,
        );

      await _pumpScreen(tester, gateway);

      await tester.tap(find.byKey(AllReviewsScreen.ratingChipKey(5)));
      await tester.pumpAndSettle();

      // Present, and findable, even though the filter hides it.
      expect(find.text('Your review'), findsOneWidget);
expect(find.byKey(const Key('reviews-pinned-mine')), findsOneWidget);
      // And the caller is told why it is up there.
      expect(find.textContaining('shown above the list'), findsOneWidget);
    });

    testWidgets('is pinned even when the filter matches nothing at all', (
      tester,
    ) async {
      final mine = aReview(id: 'MINE', rating: 2, reviewer: 'Me', isMine: true);

      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: [mine], myReview: mine);

      await _pumpScreen(tester, gateway);

      // Nothing matches the band, not even the caller's own row.
      gateway.pages[1] = aPage(reviews: const [], myReview: mine);
      await _tapChip(tester, find.byKey(AllReviewsScreen.ratingChipKey(5)));

      // The own review is still reachable, and the empty state still explains
      // itself. A buyer seeing one unexplained row would assume the filter is
      // broken.
      expect(find.byKey(const Key('reviews-pinned-mine')), findsOneWidget);
      expect(find.text('No reviews match this filter.'), findsOneWidget);
    });

    testWidgets('is not duplicated when the rows already contain it', (
      tester,
    ) async {
      final mine = aReview(id: 'MINE', rating: 5, reviewer: 'Me', isMine: true);

      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: [mine, aReview(id: 'A')], myReview: mine);

      await _pumpScreen(tester, gateway);

      // One row, not a pinned copy above the same row.
      expect(find.text('Your review'), findsOneWidget);
      expect(find.byKey(const Key('reviews-pinned-mine')), findsNothing);
    });

testWidgets('a guest is not told about a review they do not have', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = aPage(reviews: _rows(2), myReview: null, canReview: false);

      await _pumpScreen(tester, gateway);

      expect(find.text('Your review'), findsNothing);
      expect(find.text('Edit yours'), findsNothing);
    });

    testWidgets('a blocked reviewer is still told why they cannot write', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = ReviewPageResult(
          reviews: _rows(1),
          summary: const RatingSummary(average: 4.0, count: 1),
          canReview: false,
          blockedReason: 'You cannot review your own listing.',
        );

      await _pumpScreen(tester, gateway);

      // A disabled button cannot say why; the server's sentence is shown instead,
      // and no edit or delete control is offered.
      expect(find.text('You cannot review your own listing.'), findsOneWidget);
      expect(find.text('Edit yours'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('a guest sign-in reason does not clutter the header', (
      tester,
    ) async {
      final gateway = RecordingGateway()
        ..pages[1] = ReviewPageResult(
          reviews: _rows(1),
          summary: const RatingSummary(average: 4.0, count: 1),
          canReview: false,
          blockedReason: 'Sign in to write a review.',
        );

      await _pumpScreen(tester, gateway);

      // Not shown as a reason here: the product page already offers sign-in in
      // context, and repeating it above a list of other people's reviews reads
      // as an error.
      expect(find.text('Sign in to write a review.'), findsNothing);
    });
  });

  ratingLabelAndCardTests();
}
  /// The two shared display widgets, tested here because the screen above is
/// their main consumer and the product page is the other.
void ratingLabelAndCardTests() {
  group('CompactRatingLabel', () {
    testWidgets('shows one star, the average and the count', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactRatingLabel(
              summary: RatingSummary(average: 4.5, count: 12),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(12)'), findsOneWidget);
      // Not the five drawn stars: that is the detail-page treatment.
      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('renders nothing at all when unreviewed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactRatingLabel(summary: RatingSummary.none()),
          ),
        ),
      );

      expect(find.byIcon(Icons.star), findsNothing);
      // Specifically no "0.0" and no "0": a new listing has not been judged.
      expect(find.textContaining('0'), findsNothing);
    });

    testWidgets('shows the average without a count when asked', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactRatingLabel(
              summary: RatingSummary(average: 4, count: 3),
              showCount: false,
            ),
          ),
        ),
      );

      expect(find.text('4.0'), findsOneWidget);
      expect(find.text('(3)'), findsNothing);
    });
  });

  group('ReviewCard', () {
    Future<void> pump(WidgetTester tester, ListingReview review) async {
      _usePhone(tester);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ReviewCard(review: review))),
      );
    }

    testWidgets('puts the stars right of the reviewer', (tester) async {
      await pump(tester, aReview(reviewer: 'Maria S.'));

      final name = tester.getTopLeft(find.text('Maria S.'));
      final stars = tester.getTopLeft(find.byType(RatingStars));

      // Not a prefix of the name, but a column at the far end, so scores can be
      // scanned down a list instead of read one at a time.
      expect(stars.dx, greaterThan(name.dx));
    });

    testWidgets('a long reviewer name ellipsizes and keeps the stars', (
      tester,
    ) async {
      await pump(tester, aReview(reviewer: 'A very long reviewer name indeed'));

      expect(tester.takeException(), isNull);
      expect(find.byType(RatingStars), findsOneWidget);
    });

testWidgets('shows the date under the name, not under the stars', (
      tester,
    ) async {
      final review = aReview(reviewer: 'Maria S.');
      await pump(tester, review);

      // Matched on the model's own label rather than a date pattern: the label
      // is relative ("4 days ago"), so searching for a year finds nothing.
      final name = tester.getBottomLeft(find.text('Maria S.'));
      final date = tester.getTopLeft(find.text(review.createdLabel));

      // Belongs to the person: below the name, above the comment.
      expect(date.dy, greaterThanOrEqualTo(name.dy));
    });

    testWidgets('a bare star rating prints no empty comment line', (
      tester,
    ) async {
      await pump(tester, aReview(comment: null));

      expect(find.byType(RatingStars), findsOneWidget);
      expect(find.text('Very fresh, big crates.'), findsNothing);
    });

    testWidgets('the own review is labelled', (tester) async {
      await pump(tester, aReview(isMine: true));

      expect(find.text('Your review'), findsOneWidget);
    });
  });
}