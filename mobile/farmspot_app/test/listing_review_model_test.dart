import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/listing_review.dart';
import 'package:flutter_test/flutter_test.dart';

// Parsing is where the display rules actually get decided, so most of these
// are about one thing: an unreviewed listing must never come out of the parser
// looking like a badly-rated one.
void main() {
  group('RatingSummary parsing', () {
    test('reads the summary block off the reviews endpoint', () {
      final summary = RatingSummary.fromJson({'average': 4.3, 'count': 7});

      expect(summary.average, 4.3);
      expect(summary.count, 7);
      expect(summary.hasRatings, isTrue);
    });

    test('reads an average the server sent as a whole number', () {
      // PHP's json_encode drops the ".0" from a whole float, so `average` is an
      // int in the JSON. Parsing this as double would throw.
      final summary = RatingSummary.fromJson({'average': 5, 'count': 1});

      expect(summary.average, 5.0);
      expect(summary.hasRatings, isTrue);
    });

    test('a null average means nobody has reviewed, which is not a zero', () {
      final summary = RatingSummary.fromJson({'average': null, 'count': 0});

      expect(summary.average, isNull);
      expect(summary.count, 0);
      expect(summary.hasRatings, isFalse);
      expect(summary.averageLabel, isEmpty);
      expect(summary.countLabel, isEmpty);
      expect(summary.filledStars, 0);
    });

    test('a missing summary block is treated as no reviews', () {
      expect(RatingSummary.fromJson(null).hasRatings, isFalse);
    });

    test('reads the server breakdown for the filter chips', () {
    final summary = RatingSummary.fromJson({
      'average': 4.3,
      'count': 9,
      'rating_breakdown': {'1': 0, '2': 1, '3': 2, '4': 3, '5': 3},
    });

    expect(summary.countFor(5), 3);
    expect(summary.countFor(1), 0);
    expect(summary.hasBreakdown, isTrue);
    // Summed to the count: a breakdown disagreeing with the total would put
    // chip counts that do not add up to the "Based on N reviews" line beside it.
    expect(
      [1, 2, 3, 4, 5].map(summary.countFor).reduce((a, b) => a + b),
      summary.count,
    );
  });

  test('a breakdown with an odd key is ignored rather than clamped', () {
    // "0" and "6" are not star ratings. Bending one onto 1 or 5 would overstate
    // a band, so it is dropped.
    final summary = RatingSummary.fromJson({
      'count': 3,
      'rating_breakdown': {'0': 5, '6': 4, 'three': 1, '5': 3},
    });

    expect(summary.countFor(5), 3);
    expect(summary.countFor(1), 0);
    expect(summary.countFor(6), 0);
  });

  test('tolerates a missing or null breakdown', () {
    // An older backend sends none at all. Chips then render without counts
    // rather than the parse failing.
    final absent = RatingSummary.fromJson({'average': 4.0, 'count': 2});
    final nulled = RatingSummary.fromJson({
      'average': 4.0,
      'count': 2,
      'rating_breakdown': null,
    });

    expect(absent.hasBreakdown, isFalse);
    expect(absent.countFor(5), 0);
    expect(nulled.hasBreakdown, isFalse);
    expect(nulled.countFor(5), 0);
  });

  test('ReviewSort parses the wire values and falls back to newest', () {
    expect(ReviewSort.fromWire('best'), ReviewSort.best);
    expect(ReviewSort.fromWire('lowest'), ReviewSort.lowest);
    // An unknown value from a newer server must not blank a list being read.
    expect(ReviewSort.fromWire('sideways'), ReviewSort.newest);
    expect(ReviewSort.fromWire(null), ReviewSort.newest);
    // Wire values are what the endpoint expects, spelled exactly.
    for (final sort in ReviewSort.values) {
      expect(sort.wireValue, isNotEmpty);
    }
  });

  test('ReviewFilter only sends parameters that are doing something', () {
    // Untouched: nothing added, so the request is byte-identical to the one
    // that existed before filtering.
    expect(const ReviewFilter.all().toQuery(), isEmpty);
    expect(const ReviewFilter.all().toQuery(sort: ReviewSort.newest), isEmpty);

    expect(const ReviewFilter.all().toQuery(sort: ReviewSort.best), {
      'sort': 'best',
    });
    expect(const ReviewFilter(rating: 4).toQuery(), {'rating': '4'});

    // Star selection and comments are independent parameters, so they combine
    // without the backend needing to understand a combined token.
    expect(
      const ReviewFilter(rating: 4, withCommentsOnly: true).toQuery(),
      {'rating': '4', 'with_comment': 'true'},
    );

    // withComments(false) is deliberately not sent: it would mean "only bare
    // star ratings", which is not what an untouched screen means.
    expect(
      const ReviewFilter(rating: 4, withCommentsOnly: false).toQuery(),
      {'rating': '4'},
    );
  });

  test('ReviewFilter toggles one axis and keeps the other', () {
    const start = ReviewFilter(rating: 3);

    expect(start.withComments(true).rating, 3);
    expect(start.withComments(true).withCommentsOnly, isTrue);
    expect(start.withRating(5).withCommentsOnly, isFalse);
    expect(const ReviewFilter.all().withRating(2).isActive, isTrue);
    expect(const ReviewFilter.all().isActive, isFalse);
    // Two filters with the same selection compare equal, so the screen can tell a
    // real change from a re-selection of what is already active.
    expect(const ReviewFilter(rating: 2), const ReviewFilter(rating: 2));
    expect(const ReviewFilter(rating: 2), isNot(const ReviewFilter(rating: 3)));
  });

  test('ListingReviewsPage knows whether the loaded rows include mine', () {
    final mine = ListingReview(
      id: 'LRVMINE',
      listingId: 'LST0001',
      rating: 2,
      comment: null,
      reviewer: 'Me',
      createdAt: '2026-10-01T08:30:00Z',
      updatedAt: '2026-10-01T08:30:00Z',
      isMine: true,
    );
    final other = ListingReview(
      id: 'LRVOTHER',
      listingId: 'LST0001',
      rating: 5,
      comment: null,
      reviewer: 'Maria S.',
      createdAt: '2026-10-01T08:30:00Z',
      updatedAt: '2026-10-01T08:30:00Z',
    );

    // The own review exists but a filter excluded it: still findable, which is
    // why the list screen pins it above the rows.
    final hidden = ListingReviewsPage(myReview: mine);
    expect(hidden.hasMine, isTrue);
    expect(hidden.listsMine, isFalse);

    // Present in the loaded rows: no second copy gets pinned above it.
    final listed = ListingReviewsPage(reviews: [mine, other], myReview: mine);
    expect(listed.listsMine, isTrue);

    // No own review at all.
    final guest = ListingReviewsPage(reviews: [other]);
    expect(guest.hasMine, isFalse);
    expect(guest.listsMine, isFalse);
  });

  test('a count with no average does not render as a rating', () {
      // Malformed, but a lone "4.0" over an empty list is worse than hiding.
      final summary = RatingSummary.fromJson({'average': null, 'count': 4});

      expect(summary.hasRatings, isFalse);
    });

    test('reads the flat rating pair off a listing payload', () {
      final summary = RatingSummary.fromListingJson({
        'rating_average': 3.5,
        'rating_count': 2,
      });

      expect(summary.average, 3.5);
      expect(summary.count, 2);
    });

    test('a listing payload without the rating fields is unrated', () {
      // The endpoint did not opt in to the summary, so it must read as unrated
      // rather than as a zero-star listing.
      final summary = RatingSummary.fromListingJson({'id': 'ABC123'});

      expect(summary.hasRatings, isFalse);
      expect(summary.average, isNull);
    });

    test('a listing payload with a null average is unrated', () {
      final summary = RatingSummary.fromListingJson({
        'rating_average': null,
        'rating_count': 0,
      });

      expect(summary.hasRatings, isFalse);
    });
  });

  group('RatingSummary display values', () {
    test('shows one decimal so 4 never reads as a dropped digit', () {
      expect(const RatingSummary(average: 4, count: 3).averageLabel, '4.0');
    });

    test('rounds to one decimal', () {
      expect(
        const RatingSummary(average: 4.333333, count: 3).averageLabel,
        '4.3',
      );
    });

    test('count label is singular for exactly one review', () {
      expect(const RatingSummary(average: 5, count: 1).countLabel, '1 review');
      expect(const RatingSummary(average: 5, count: 4).countLabel, '4 reviews');
    });

    test('filled stars round down, never past five', () {
      expect(const RatingSummary(average: 4.9, count: 2).filledStars, 4);
      expect(const RatingSummary(average: 5, count: 1).filledStars, 5);
      expect(const RatingSummary(average: 0.4, count: 1).filledStars, 0);
    });
  });

  group('ListingReview parsing', () {
    Map<String, dynamic> row({
      String id = 'LRV001',
      String listingId = 'LST001',
      int rating = 5,
      String? comment = 'Excellent',
      String reviewer = 'Maria S.',
      String? createdAt = '2026-10-01T08:30:00Z',
      bool isMine = false,
    }) {
      return {
        'id': id,
        'listing_id': listingId,
        'rating': rating,
        'comment': comment,
        'reviewer': reviewer,
        'created_at': createdAt,
        'updated_at': createdAt,
        'is_mine': isMine,
      };
    }

    test('reads a full row', () {
      final review = ListingReview.fromJson(row());

      expect(review.id, 'LRV001');
      expect(review.listingId, 'LST001');
      expect(review.rating, 5);
      expect(review.comment, 'Excellent');
      expect(review.reviewer, 'Maria S.');
      expect(review.isMine, isFalse);
      expect(review.hasComment, isTrue);
    });

    test('a null comment means the reviewer left stars only', () {
      final review = ListingReview.fromJson(row(comment: null));

      expect(review.comment, isNull);
      expect(review.hasComment, isFalse);
    });

    test('a whitespace-only comment counts as no comment', () {
      // The server trims, so it would send null — but a stray blank string must
      // not render an empty comment block.
      final review = ListingReview.fromJson(row(comment: '   '));

      expect(review.comment, isNull);
      expect(review.hasComment, isFalse);
    });

    test('clamps a rating outside 1..5 rather than trusting it', () {
      // The CHECK constraint means the server cannot store one, but a bad
      // response must not make the star row loop wrong.
      expect(ListingReview.fromJson(row(rating: 9)).rating, 5);
      expect(ListingReview.fromJson(row(rating: 0)).rating, 1);
    });

    test('falls back to a neutral reviewer rather than an empty byline', () {
      expect(ListingReview.fromJson(row(reviewer: '')).reviewer, 'A buyer');
    });

    test('marks the caller own review', () {
      expect(ListingReview.fromJson(row(isMine: true)).isMine, isTrue);
    });

    test('labels a recent review by minutes, hours and days', () {
      final now = DateTime.now();

      expect(
        ListingReview.fromJson(
          row(
            createdAt: now
                .subtract(const Duration(seconds: 10))
                .toIso8601String(),
          ),
        ).createdLabel,
        'just now',
      );
      expect(
        ListingReview.fromJson(
          row(
            createdAt: now
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
          ),
        ).createdLabel,
        '5 minutes ago',
      );
      expect(
        ListingReview.fromJson(
          row(
            createdAt: now.subtract(const Duration(hours: 3)).toIso8601String(),
          ),
        ).createdLabel,
        '3 hours ago',
      );
      expect(
        ListingReview.fromJson(
          row(
            createdAt: now.subtract(const Duration(days: 4)).toIso8601String(),
          ),
        ).createdLabel,
        '4 days ago',
      );
    });

    test('an unparseable date produces no label rather than "today"', () {
      expect(
        ListingReview.fromJson(row(createdAt: 'nope')).createdLabel,
        isEmpty,
      );
      expect(
        ListingReview.fromJson(row(createdAt: null)).createdLabel,
        isEmpty,
      );
    });
  });

  group('ListingReviewsPage', () {
    Map<String, dynamic> response({
      List<Map<String, dynamic>>? reviews,
      Object? average = 4.0,
      int count = 2,
      Map<String, dynamic>? myReview,
      bool canReview = true,
      String? blockedReason,
      int currentPage = 1,
      int lastPage = 1,
    }) {
      return {
        'reviews': reviews ?? [],
        'summary': {'average': average, 'count': count},
        'my_review': myReview,
        'can_review': canReview,
        'review_blocked_reason': blockedReason,
        'current_page': currentPage,
        'last_page': lastPage,
        'per_page': 5,
        'total': count,
      };
    }

    Map<String, dynamic> row(String id, int rating, String createdAt) => {
      'id': id,
      'listing_id': 'LST001',
      'rating': rating,
      'comment': null,
      'reviewer': 'Someone S.',
      'created_at': createdAt,
      'updated_at': createdAt,
      'is_mine': false,
    };

    test('parses the whole endpoint response', () {
      final page = ListingReviewsPage.fromJson(
        response(reviews: [row('A', 5, '2026-10-02T00:00:00Z')]),
      );

      expect(page.reviews, hasLength(1));
      expect(page.summary.average, 4.0);
      expect(page.summary.count, 2);
      expect(page.canReview, isTrue);
      expect(page.blockedReason, isNull);
      expect(page.hasMine, isFalse);
    });

    test('a guest gets no my_review and cannot review', () {
      final page = ListingReviewsPage.fromJson(
        response(canReview: false, blockedReason: 'Sign in to write a review.'),
      );

      expect(page.myReview, isNull);
      expect(page.canReview, isFalse);
      expect(page.blockedReason, 'Sign in to write a review.');
      expect(page.writeActionLabel, 'Write a review');
    });

    test('a blocked reviewer still reads the public list', () {
      final page = ListingReviewsPage.fromJson(
        response(
          reviews: [row('A', 5, '2026-10-02T00:00:00Z')],
          canReview: false,
          blockedReason: 'This is your own listing.',
        ),
      );

      expect(page.reviews, hasLength(1));
      expect(page.writeActionLabel, 'Write a review');
    });

    test('an existing review switches the button to edit', () {
      final page = ListingReviewsPage.fromJson(
        response(
          myReview: {
            'id': 'MINE',
            'listing_id': 'LST001',
            'rating': 3,
            'comment': 'Mine',
            'reviewer': 'Me M.',
            'created_at': '2026-10-01T00:00:00Z',
            'updated_at': '2026-10-01T00:00:00Z',
            'is_mine': true,
          },
        ),
      );

      expect(page.hasMine, isTrue);
      expect(page.myReview!.rating, 3);
      expect(page.myReview!.comment, 'Mine');
      expect(page.writeActionLabel, 'Edit your review');
    });

    test('knows when another page exists', () {
      final page = ListingReviewsPage.fromJson(
        response(currentPage: 1, lastPage: 3),
      );

      expect(page.hasMorePages, isTrue);
      expect(
        ListingReviewsPage.fromJson(
          response(currentPage: 3, lastPage: 3),
        ).hasMorePages,
        isFalse,
      );
    });

    test('saving splices the row in and updates the summary in one step', () {
      final page = ListingReviewsPage.fromJson(
        response(
          reviews: [row('A', 5, '2026-10-03T00:00:00Z')],
          average: 5.0,
          count: 1,
        ),
      );

      final saved = ListingReview.fromJson({
        'id': 'MINE',
        'listing_id': 'LST001',
        'rating': 4,
        'comment': 'Good',
        'reviewer': 'Me M.',
        'created_at': '2026-10-04T00:00:00Z',
        'updated_at': '2026-10-04T00:00:00Z',
        'is_mine': true,
      });

      final after = page.withSavedReview(
        saved,
        const RatingSummary(average: 4.5, count: 2),
      );

      expect(after.reviews, hasLength(2));
      // Newest first: the review just saved is the one written most recently.
      expect(after.reviews.first.id, 'MINE');
      expect(after.myReview!.id, 'MINE');
      expect(after.summary.average, 4.5);
      expect(after.total, 2);
      // Can still review after having reviewed: one row per user, edits are
      // allowed.
      expect(after.writeActionLabel, 'Edit your review');
    });

    test('re-saving replaces the existing row rather than duplicating it', () {
      final mine = ListingReview.fromJson({
        'id': 'MINE',
        'listing_id': 'LST001',
        'rating': 2,
        'comment': null,
        'reviewer': 'Me M.',
        'created_at': '2026-10-04T00:00:00Z',
        'updated_at': '2026-10-04T00:00:00Z',
        'is_mine': true,
      });

      final page = ListingReviewsPage(
        reviews: [mine],
        summary: const RatingSummary(average: 2.0, count: 1),
        myReview: mine,
        canReview: true,
        total: 1,
      );

      final edited = ListingReview.fromJson({
        'id': 'MINE',
        'listing_id': 'LST001',
        'rating': 5,
        'comment': 'On reflection, great',
        'reviewer': 'Me M.',
        'created_at': '2026-10-04T00:00:00Z',
        'updated_at': '2026-10-04T00:00:00Z',
        'is_mine': true,
      });

      final after = page.withSavedReview(
        edited,
        const RatingSummary(average: 5.0, count: 1),
      );

      expect(after.reviews, hasLength(1));
      expect(after.reviews.single.id, 'MINE');
      expect(after.reviews.single.rating, 5);
      expect(after.summary.average, 5.0);
    });

    test(
      'deleting drops the row, the prefill state and the count together',
      () {
        final mine = ListingReview.fromJson({
          'id': 'MINE',
          'listing_id': 'LST001',
          'rating': 1,
          'comment': null,
          'reviewer': 'Me M.',
          'created_at': '2026-10-04T00:00:00Z',
          'updated_at': '2026-10-04T00:00:00Z',
          'is_mine': true,
        });

        final page = ListingReviewsPage(
          reviews: [mine],
          summary: const RatingSummary(average: 1.0, count: 1),
          myReview: mine,
          canReview: true,
          total: 1,
        );

        final after = page.withoutReview('MINE', const RatingSummary.none());

        expect(after.reviews, isEmpty);
        expect(after.myReview, isNull);
        expect(after.summary.hasRatings, isFalse);
        expect(after.summary.average, isNull);
        expect(after.total, 0);
        // Back to the write state, ready for a fresh review.
        expect(after.writeActionLabel, 'Write a review');
      },
    );

    test('deleting someone else row is not possible by accident', () {
      // A delete response only ever carries the caller's own summary, so this
      // guards against a mismatched id quietly taking the list out of sync.
      final page = ListingReviewsPage(
        reviews: [
          ListingReview.fromJson({
            'id': 'THEIRS',
            'listing_id': 'LST001',
            'rating': 5,
            'comment': null,
            'reviewer': 'Them T.',
            'created_at': '2026-10-01T00:00:00Z',
            'updated_at': '2026-10-01T00:00:00Z',
            'is_mine': false,
          }),
        ],
        summary: const RatingSummary(average: 5.0, count: 1),
        total: 1,
      );

      final after = page.withoutReview('MINE', const RatingSummary.none());

      expect(after.reviews, hasLength(1));
    });
  });

  group('ReviewDraft', () {
    test('sends the rating with an optional comment', () {
      const withComment = ReviewDraft(rating: 4, comment: 'Good crop');
      expect(withComment.toJson(), {'rating': 4, 'comment': 'Good crop'});
    });

    test('omits the comment key entirely when there is none', () {
      expect(const ReviewDraft(rating: 3).toJson(), {'rating': 3});
    });

    test('omits a whitespace-only comment rather than sending blank', () {
      const draft = ReviewDraft(rating: 3, comment: '   \n  ');
      expect(draft.toJson(), {'rating': 3});
    });

    test('trims the comment it sends', () {
      const draft = ReviewDraft(rating: 3, comment: '  Nice.  ');
      expect(draft.toJson(), {'rating': 3, 'comment': 'Nice.'});
    });
  });

  group('Listing carries its rating', () {
    test('parses the rating pair off a listing payload', () {
      final listing = Listing.fromJson({
        'id': 'LST001',
        'status': 'AVAILABLE_NOW',
        'crop_icon': 'Carrot',
        'rating_average': 4.2,
        'rating_count': 5,
      });

      expect(listing.ratings.average, 4.2);
      expect(listing.ratings.count, 5);
      expect(listing.ratings.hasRatings, isTrue);
    });

    test('an older payload with no rating fields is unrated', () {
      final listing = Listing.fromJson({
        'id': 'LST001',
        'status': 'AVAILABLE_NOW',
        'crop_icon': 'Carrot',
      });

      expect(listing.ratings.hasRatings, isFalse);
    });

    test('an unreviewed listing keeps a null average, not zero', () {
      final listing = Listing.fromJson({
        'id': 'LST001',
        'status': 'AVAILABLE_NOW',
        'crop_icon': 'Carrot',
        'rating_average': null,
        'rating_count': 0,
      });

      expect(listing.ratings.average, isNull);
      expect(listing.ratings.hasRatings, isFalse);
    });

    test('the rating survives conversion to the UI-facing shape', () {
      final listing = Listing.fromJson({
        'id': 'LST001',
        'status': 'AVAILABLE_NOW',
        'crop_icon': 'Carrot',
        'rating_average': 5,
        'rating_count': 1,
      });

      // toCropListing() rebuilds the object field by field, so this is the
      // check that a rated listing does not lose its stars on the way to a card.
      final crop = listing.toCropListing();

      expect(crop.ratings.average, 5.0);
      expect(crop.ratings.count, 1);
      expect(crop.ratings.hasRatings, isTrue);
    });

    test('an unrated listing passes through with no stars to render', () {
      final crop = Listing.fromJson({
        'id': 'LST001',
        'status': 'AVAILABLE_NOW',
        'crop_icon': 'Carrot',
      }).toCropListing();

      expect(crop.ratings.hasRatings, isFalse);
    });
  });
}
