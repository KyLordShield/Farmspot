import 'dart:async';

import 'package:farmspot_app/models/listing_review.dart';
import 'package:farmspot_app/services/review_service.dart';
import 'package:farmspot_app/widgets/listing_reviews_section.dart';
import 'package:farmspot_app/widgets/rating_stars.dart';
import 'package:farmspot_app/widgets/review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------------ fixtures

/// Recording stand-in for the review endpoints.
///
/// [pages] is keyed by page number so paging can be tested for real: the fake
/// serves the same payload shape the controller does, including `can_review`
/// and `my_review`, which is the part that silently broke once already.
class FakeReviewsGateway implements ReviewsGateway {
  final Map<int, ReviewPageResult> pages = {};

  final List<ReviewDraft> saved = [];
  int saveCalls = 0;
  int deleteCalls = 0;

  /// Set to make the matching call throw.
  String? fetchError;
  String? saveError;
  String? deleteError;

  /// What [save] hands back. Overwritten per test to mirror a real write.
  ReviewPageResult saveResult = const ReviewPageResult(
    reviews: [],
    summary: RatingSummary.none(),
  );

  /// What [delete] hands back.
  ReviewPageResult deleteResult = const ReviewPageResult(
    reviews: [],
    summary: RatingSummary.none(),
  );

  /// Pages requested, in order, so a duplicate fetch is caught.
  final List<int> requestedPages = [];

  /// When set, [fetch] waits on this instead of answering immediately.
  ///
  /// Needed for the state that only exists on a real network: between the
  /// screen opening and the response landing. A fake that answers in a
  /// microtask skips straight past it, which is how "the seed summary must show
  /// before the fetch lands" turns into an untested claim.
  Completer<ReviewPageResult>? pendingFetch;

  @override
  Future<ReviewPageResult> fetch({
    required String listingId,
    int page = 1,
    int perPage = 5,
  }) async {
    requestedPages.add(page);

    final pending = pendingFetch;
    if (pending != null) return pending.future;

    if (fetchError != null) throw Exception(fetchError!);
    return pages[page] ??
        const ReviewPageResult(reviews: [], summary: RatingSummary.none());
  }

  @override
  Future<ReviewPageResult> save({
    required String listingId,
    required ReviewDraft draft,
  }) async {
    saveCalls++;
    // Recorded before the error is thrown: a rejected write was still sent, and
    // asserting on it is how a test proves the app did not swallow the rating.
    saved.add(draft);
    if (saveError != null) throw Exception(saveError!);
    return saveResult;
  }

  @override
  Future<ReviewPageResult> delete(String listingId) async {
    deleteCalls++;
    if (deleteError != null) throw Exception(deleteError!);
    return deleteResult;
  }
}

ListingReview aReview({
  String id = 'LRV001',
  int rating = 5,
  String? comment = 'Very fresh, big crates.',
  String reviewer = 'Maria S.',
  bool isMine = false,
  String? createdAt,
}) {
  return ListingReview(
    id: id,
    listingId: 'LST0001',
    rating: rating,
    comment: comment,
    reviewer: reviewer,
    createdAt: createdAt ?? '2026-10-01T08:30:00Z',
    updatedAt: createdAt ?? '2026-10-01T08:30:00Z',
    isMine: isMine,
  );
}

/// What the list endpoint returns for the common case: rated, visible, and the
/// caller may write.
ReviewPageResult aPage({
  List<ListingReview> reviews = const [],
  RatingSummary summary = const RatingSummary(average: 4.3, count: 7),
  ListingReview? myReview,
  bool canReview = true,
  String? blockedReason,
  int currentPage = 1,
  int lastPage = 1,
  int total = 7,
}) {
  return ReviewPageResult(
    reviews: reviews,
    summary: summary,
    myReview: myReview,
    canReview: canReview,
    blockedReason: blockedReason,
    currentPage: currentPage,
    lastPage: lastPage,
    total: total,
  );
}

// ------------------------------------------------------------------- helpers

/// Phone-sized surface, as the report-flow tests do: the section sits far down
/// a product page, and a stretched test window hides overflow this would catch.
void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _host(
  FakeReviewsGateway gateway, {
  String listingId = 'LST0001',
  String cropName = 'carrot',
  RatingSummary initialSummary = const RatingSummary.none(),
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ListingReviewsSection(
          listingId: listingId,
          cropName: cropName,
          initialSummary: initialSummary,
          gateway: gateway,
        ),
      ),
    ),
  );
}

/// Pumps the section on a phone and lets its initial fetch settle.
Future<void> _pumpSection(
  WidgetTester tester,
  FakeReviewsGateway gateway, {
  String listingId = 'LST0001',
  String cropName = 'carrot',
  RatingSummary initialSummary = const RatingSummary.none(),
}) async {
  _usePhone(tester);
  await tester.pumpWidget(
    _host(
      gateway,
      listingId: listingId,
      cropName: cropName,
      initialSummary: initialSummary,
    ),
  );
  await tester.pumpAndSettle();
}

/// The write button, or the explanatory line that replaced it.
Finder _writeButton() => find.byKey(ListingReviewsSection.writeButtonKey);

Future<void> _tapWriteButton(WidgetTester tester) async {
  await tester.ensureVisible(_writeButton());
  await tester.pumpAndSettle();
  await tester.tap(_writeButton());
  await tester.pumpAndSettle();
}

/// A star in the sheet's tappable row.
///
/// Found through the semantics label because five identical icons have nothing
/// else to tell them apart, and a `find.text('4')` would be testing the label
/// rather than the star.
Finder _star(int n) => find.bySemanticsLabel('$n star${n == 1 ? '' : 's'}');

/// Opens the sheet and returns nothing; used by the submit/error paths.
Future<void> _openSheet(WidgetTester tester) async {
  await _tapWriteButton(tester);
}

/// Text as the section itself renders it.
///
/// Scoped to the page's scroll view rather than matched globally, because the
/// review sheet lives in an overlay that outlives the submit tap for the length
/// of the pop and snack-bar animations. Its `TextField` still holds the text
/// that was just submitted, so an unscoped `find.text` counts it twice and a
/// "the old comment is gone" assertion fails on the sheet's copy instead of on
/// a row that was really left behind.
Finder _listText(String text) => find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.text(text),
);

void main() {
  group('ListingReviewsSection reading', () {
    testWidgets('shows the average and count from the endpoint', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(reviews: [aReview()]);

      await _pumpSection(tester, gateway);

      expect(find.text('4.3'), findsOneWidget);
      expect(find.text('Based on 7 reviews'), findsOneWidget);
      expect(find.text('Reviews'), findsOneWidget);
    });

    testWidgets('renders each review with reviewer, stars and comment', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [
            aReview(id: 'A', reviewer: 'Maria S.', comment: 'Very fresh.'),
            aReview(id: 'B', rating: 3, reviewer: 'Reyes R.', comment: null),
          ],
          summary: const RatingSummary(average: 4.0, count: 2),
        );

      await _pumpSection(tester, gateway);

      expect(find.text('Maria S.'), findsOneWidget);
      expect(find.text('Very fresh.'), findsOneWidget);
      expect(find.text('Reyes R.'), findsOneWidget);
      // Stars-only review has no empty comment block.
      expect(find.text(''), findsNothing);
    });

    testWidgets('an unreviewed listing shows no stars and no 0.0', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          summary: const RatingSummary.none(),
          canReview: true,
          total: 0,
        );

      await _pumpSection(tester, gateway);

      expect(find.byType(RatingStars), findsNothing);
      expect(find.text('0.0'), findsNothing);
      expect(
        find.text('No reviews yet. Be the first to say how this crop was.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the seed summary while the fetch is in flight', (
      tester,
    ) async {
      // The card the screen was opened from already knew the average; showing it
      // immediately avoids a flash of "no reviews" on a rated listing. Held open
      // with a pending Completer because the state only exists on a real
      // network.
      final gateway = FakeReviewsGateway()
        ..pendingFetch = Completer<ReviewPageResult>();

      _usePhone(tester);
      await tester.pumpWidget(
        _host(
          gateway,
          initialSummary: const RatingSummary(average: 4.0, count: 2),
        ),
      );
      await tester.pump();

      expect(_listText('4.0'), findsOneWidget);
      expect(_listText('Based on 2 reviews'), findsOneWidget);

      // The real response then takes over.
      gateway.pendingFetch!.complete(
        aPage(
          reviews: [aReview()],
          summary: const RatingSummary(average: 4.8, count: 3),
          total: 3,
        ),
      );
      await tester.pumpAndSettle();

      expect(_listText('4.0'), findsNothing);
      expect(_listText('4.8'), findsOneWidget);
      expect(_listText('Based on 3 reviews'), findsOneWidget);
    });

    testWidgets('a single review reads "1 review", not "1 reviews"', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [aReview()],
          summary: const RatingSummary(average: 5.0, count: 1),
          total: 1,
        );

      await _pumpSection(tester, gateway);

      expect(find.text('Based on 1 review'), findsOneWidget);
    });

    testWidgets('labels the caller own review', (tester) async {
      final mine = aReview(id: 'MINE', isMine: true, comment: 'Mine.');
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [
            mine,
            aReview(id: 'THEIRS'),
          ],
          summary: const RatingSummary(average: 4.5, count: 2),
          myReview: mine,
          total: 2,
        );

      await _pumpSection(tester, gateway);

      expect(find.text('Your review'), findsOneWidget);
    });

    testWidgets('enables the write button when the server allows it', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()..pages[1] = aPage(canReview: true);

      await _pumpSection(tester, gateway);

      expect(_writeButton(), findsOneWidget);
      expect(find.text('Write a review'), findsOneWidget);
    });

    testWidgets('offers edit once the caller has reviewed', (tester) async {
      final mine = aReview(id: 'MINE', isMine: true);
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(reviews: [mine], myReview: mine);

      await _pumpSection(tester, gateway);

      expect(find.text('Edit your review'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a guest is told to sign in instead of getting a button', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          canReview: false,
          blockedReason: 'Sign in to write a review.',
        );

      await _pumpSection(tester, gateway);

      expect(_writeButton(), findsNothing);
      expect(
        find.text('Sign in to write a review for this crop.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the servers reason verbatim for a blocked reviewer', (
      tester,
    ) async {
      // The per-rule wording is the point: "This is your own listing." says
      // something a generic "you cannot review this" does not.
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          canReview: false,
          blockedReason: 'This is your own listing.',
        );

      await _pumpSection(tester, gateway);

      expect(_writeButton(), findsNothing);
      expect(find.text('This is your own listing.'), findsOneWidget);
    });

    testWidgets('a fetch failure shows an error and a retry', (tester) async {
      final gateway = FakeReviewsGateway()
        ..fetchError = 'Could not load reviews.';

      await _pumpSection(tester, gateway);

      expect(find.text('Could not load reviews.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(_writeButton(), findsNothing);
    });

    testWidgets('retry re-fetches once and clears the error', (tester) async {
      final gateway = FakeReviewsGateway()
        ..fetchError = 'Could not load reviews.';
      await _pumpSection(tester, gateway);

      gateway.fetchError = null;
      gateway.pages[1] = aPage(reviews: [aReview()]);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load reviews.'), findsNothing);
      expect(find.text('Maria S.'), findsOneWidget);
      expect(gateway.requestedPages, [1, 1]);
    });

    testWidgets('asks for exactly one page on open', (tester) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(reviews: [aReview()], lastPage: 3);

      await _pumpSection(tester, gateway);

      // A second fetch here would double-load and could reorder the list.
      expect(gateway.requestedPages, [1]);
    });
  });

  group('ListingReviewsSection paging', () {
    testWidgets('appends the next page without dropping what is shown', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [aReview(id: 'A', reviewer: 'Maria S.')],
          summary: const RatingSummary(average: 4.0, count: 2),
          currentPage: 1,
          lastPage: 2,
          total: 2,
        )
        ..pages[2] = aPage(
          reviews: [aReview(id: 'B', reviewer: 'Reyes R.', rating: 4)],
          summary: const RatingSummary(average: 4.0, count: 2),
          currentPage: 2,
          lastPage: 2,
          total: 2,
        );

      await _pumpSection(tester, gateway);

      expect(find.text('Show more reviews'), findsOneWidget);
      await tester.tap(find.text('Show more reviews'));
      await tester.pumpAndSettle();

      expect(gateway.requestedPages, [1, 2]);
      expect(find.text('Maria S.'), findsOneWidget);
      expect(find.text('Reyes R.'), findsOneWidget);
      // The summary is unchanged by paging, and is not overwritten by the
      // page-two response's copy of it.
      expect(find.text('Based on 2 reviews'), findsOneWidget);
      expect(find.text('Show more reviews'), findsNothing);
    });
  });

  group('ListingReviewsSection writing', () {
    testWidgets('sends the chosen stars and comment', (tester) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(canReview: true)
        ..saveResult = ReviewPageResult(
          reviews: const [],
          summary: const RatingSummary(average: 4.0, count: 1),
          savedReview: aReview(id: 'MINE', isMine: true, comment: 'Good.'),
        );

      await _pumpSection(tester, gateway);
      await _openSheet(tester);

      await tester.tap(_star(4));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Good.');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('review-sheet-submit')));
      await tester.pumpAndSettle();

      expect(gateway.saveCalls, 1);
      expect(gateway.saved.single.rating, 4);
      expect(gateway.saved.single.comment!.trim(), 'Good.');
      // The response's own row and summary are merged in, so the new review
      // shows without a refetch.
      expect(find.text('Review submitted.'), findsOneWidget);
      expect(_listText('Based on 1 review'), findsOneWidget);
      expect(_listText('Your review'), findsOneWidget);
    });

    testWidgets('a comment-only submission omits the comment key', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(canReview: true)
        ..saveResult = ReviewPageResult(
          reviews: const [],
          summary: const RatingSummary(average: 3.0, count: 1),
          savedReview: aReview(id: 'MINE', isMine: true, comment: null),
        );

      await _pumpSection(tester, gateway);
      await _openSheet(tester);

      await tester.tap(_star(3));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-sheet-submit')));
      await tester.pumpAndSettle();

      expect(gateway.saved.single.rating, 3);
      expect(gateway.saved.single.toJson(), {'rating': 3});
    });

    testWidgets('editing replaces the existing row instead of duplicating it', (
      tester,
    ) async {
      final mine = aReview(
        id: 'MINE',
        rating: 2,
        isMine: true,
        comment: 'Meh.',
      );
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [mine],
          summary: const RatingSummary(average: 2.0, count: 1),
          myReview: mine,
          total: 1,
        )
        ..saveResult = ReviewPageResult(
          reviews: const [],
          summary: const RatingSummary(average: 5.0, count: 1),
          savedReview: aReview(
            id: 'MINE',
            rating: 5,
            isMine: true,
            comment: 'On reflection, great.',
          ),
        );

      await _pumpSection(tester, gateway);

      // Opens filled in from my_review: the sheet is the same form, pre-seeded, so
      // the existing rating and comment are already in it before any typing.
      await _openSheet(tester);
      expect(find.text('Update review'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Meh.',
      );
      expect(_listText('Meh.'), findsOneWidget);

      await tester.tap(_star(5));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'On reflection, great.');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('review-sheet-submit')));
      await tester.pumpAndSettle();

      expect(gateway.saved.single.rating, 5);
      expect(find.text('Review updated.'), findsOneWidget);

      expect(_listText('On reflection, great.'), findsOneWidget);
      expect(_listText('Meh.'), findsNothing);
      expect(_listText('Your review'), findsOneWidget);
      // Twice, and correctly so: the recomputed header average and the saved
      // row's own five stars.
      expect(_listText('5.0'), findsNWidgets(2));
    });

    testWidgets('shows the servers rejection reason and keeps the button', (
      tester,
    ) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(canReview: true)
        ..saveError = 'This is your own listing.';

      await _pumpSection(tester, gateway);
      await _openSheet(tester);

      await tester.tap(_star(5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-sheet-submit')));
      await tester.pumpAndSettle();

      expect(gateway.saveCalls, 1);
      expect(gateway.saved, hasLength(1));
      expect(find.text('This is your own listing.'), findsOneWidget);
      // Nothing was written, so the section still offers to write.
      expect(find.text('Write a review'), findsOneWidget);
    });
  });

  group('ListingReviewsSection deleting', () {
    testWidgets('confirming removes the row and updates the average', (
      tester,
    ) async {
      final mine = aReview(id: 'MINE', rating: 1, isMine: true, comment: null);
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [
            mine,
            aReview(id: 'THEIRS'),
          ],
          summary: const RatingSummary(average: 3.0, count: 2),
          myReview: mine,
          total: 2,
        )
        ..deleteResult = const ReviewPageResult(
          reviews: [],
          summary: RatingSummary(average: 5.0, count: 1),
        );

      await _pumpSection(tester, gateway);

      await tester.ensureVisible(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your review?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(gateway.deleteCalls, 1);
      expect(find.text('Your review was deleted.'), findsOneWidget);
      expect(_listText('Your review'), findsNothing);
      expect(_listText('Write a review'), findsOneWidget);
      // The remaining review plus the recomputed header both read 5.0 now.
      expect(_listText('5.0'), findsNWidgets(2));
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final mine = aReview(id: 'MINE', isMine: true);
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [mine],
          summary: const RatingSummary(average: 4.0, count: 1),
          myReview: mine,
          total: 1,
        );

      await _pumpSection(tester, gateway);

      await tester.ensureVisible(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(gateway.deleteCalls, 0);
      expect(find.text('Your review'), findsOneWidget);
      expect(find.text('Edit your review'), findsOneWidget);
    });

    testWidgets('a delete failure leaves the review in place', (tester) async {
      final mine = aReview(id: 'MINE', isMine: true);
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(
          reviews: [mine],
          summary: const RatingSummary(average: 4.0, count: 1),
          myReview: mine,
          total: 1,
        )
        ..deleteError = 'Could not delete your review.';

      await _pumpSection(tester, gateway);

      await tester.ensureVisible(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(gateway.deleteCalls, 1);
      expect(find.text('Could not delete your review.'), findsOneWidget);
      expect(find.text('Your review'), findsOneWidget);
      expect(find.text('Edit your review'), findsOneWidget);
    });

    testWidgets('no delete affordance without an own review', (tester) async {
      final gateway = FakeReviewsGateway()
        ..pages[1] = aPage(reviews: [aReview(id: 'THEIRS')]);

      await _pumpSection(tester, gateway);

      expect(find.text('Delete'), findsNothing);
    });
  });

  group('Review sheet', () {
    testWidgets('submit is disabled until a star is picked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showReviewSheetFor(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('review-sheet-submit'));
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);
      expect(find.text('Tap a star to rate'), findsOneWidget);

      await tester.tap(_star(4));
      await tester.pumpAndSettle();

      expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);
      expect(find.text('Good'), findsOneWidget);
    });

    testWidgets('dismissing sends nothing back', (tester) async {
      // Starts as a non-null value so a null return is proof the sheet reported
      // a dismissal rather than the callback never having run.
      ReviewDraft? returned = const ReviewDraft(rating: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returned = await showReviewSheetFor(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(_star(5));
      await tester.pumpAndSettle();

      // Drag the sheet away rather than tapping outside, which is what a cancel
      // looks like on a device.
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      // Null: a dismissed sheet must not report a submission, however many stars
      // were tapped before it went away.
      expect(returned, isNull);
    });

    testWidgets('shows the running average when there is one', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showReviewSheetFor(
                    context,
                    summary: const RatingSummary(average: 4.3, count: 7),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('4.3'), findsOneWidget);
      expect(find.text('so far'), findsOneWidget);
    });

    testWidgets('names the crop being reviewed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showReviewSheetFor(context, cropName: 'labanos'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('labanos'), findsOneWidget);
      expect(find.text('Write a review'), findsOneWidget);
    });
  });
}

/// Opens the sheet the way the section does, with the same defaults.
Future<ReviewDraft?> showReviewSheetFor(
  BuildContext context, {
  String cropName = 'carrot',
  RatingSummary summary = const RatingSummary.none(),
  ListingReview? existing,
}) {
  return showReviewSheet(
    context: context,
    listingId: 'LST0001',
    cropName: cropName,
    summary: summary,
    existing: existing,
  );
}
