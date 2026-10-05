/// Rating summary and review list for one listing.
///
/// One file for both the wire shapes the reviews endpoint returns: the
/// `{average, count}` block and a single review row. They are always used
/// together — a listing's reviews are not shown without the summary above them,
/// and the summary is not shown without the list — so keeping them adjacent
/// keeps the null-handling rules in one place.
///
/// The null handling is the whole point of this file. The backend sends
/// `average: null` for a listing nobody has reviewed, and `null` must never
/// become 0: showing "0.0" or an empty star row on a brand new listing claims
/// buyers already judged it badly. [hasRatings] is what gates every render.
library;

/// `{average, count}` from GET /api/listings/{id}/reviews, and the
/// `rating_average` / `rating_count` pair on a listing payload.
class RatingSummary {
  /// Mean of the visible review ratings, or null when there are none.
  final double? average;

  /// How many visible reviews the average is over.
  final int count;

  const RatingSummary({this.average, this.count = 0});

  const RatingSummary.none() : average = null, count = 0;

  /// Parses the endpoint's `summary` block.
  factory RatingSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RatingSummary.none();

    final rawAverage = json['average'];
    final rawCount = json['count'];

    return RatingSummary(
      // A JSON null and a missing key mean the same thing here: unrated.
      // jsonDecode gives a num for a present value, and an int where PHP's
      // json_encode dropped the ".0" from a whole number, so this has to read
      // as num rather than double or the parse throws on `average: 5`.
      average: rawAverage == null ? null : (rawAverage as num).toDouble(),
      count: rawCount is num ? rawCount.toInt() : 0,
    );
  }

  /// Builds from a listing payload's `rating_average` / `rating_count` pair.
  ///
  /// Separate from [fromJson] because the listing payload spreads the two values
  /// across the listing object while the reviews endpoint nests them under
  /// `summary`, and because the listing fields may be absent entirely on an
  /// endpoint that did not ask for them.
  factory RatingSummary.fromListingJson(Map<String, dynamic> json) {
    final rawAverage = json['rating_average'];
    final rawCount = json['rating_count'];

    return RatingSummary(
      average: rawAverage == null ? null : (rawAverage as num).toDouble(),
      count: rawCount is num ? rawCount.toInt() : 0,
    );
  }

  /// Whether anything has been rated.
  ///
  /// Requires a non-null average AND a positive count, so a malformed payload
  /// that sends one without the other renders nothing rather than a lone "3.0"
  /// with no reviews under it.
  bool get hasRatings => average != null && count > 0;

  /// Half-star step for drawing a filled star row, e.g. 4.3 -> 4.
  ///
  /// Rounded down on purpose. Filling half the fifth star for a 4.3 needs
  /// half-pixel glyphs and reads as noise at card size; the exact number is
  /// always printed next to it.
  int get filledStars {
    final value = average;
    if (value == null) return 0;
    return value.floor().clamp(0, 5);
  }

  /// The average as shown to a buyer: one decimal, always.
  ///
  /// `4.0` rather than `4` on purpose. Listing "4.0" next to "3" from a
  /// one-review listing reads as a deliberate score; a bare "4" looks like the
  /// app dropped a digit.
  String get averageLabel => average == null ? '' : average!.toStringAsFixed(1);

  /// "1 review" / "4 reviews" / "" when unrated.
  String get countLabel {
    if (count <= 0) return '';
    return count == 1 ? '1 review' : '$count reviews';
  }

  RatingSummary copyWith({double? average, int? count}) {
    return RatingSummary(
      average: average ?? this.average,
      count: count ?? this.count,
    );
  }

  @override
  String toString() => 'RatingSummary(average: $average, count: $count)';
}

/// One row from the `reviews` array.
class ListingReview {
  final String id;

  /// LST_ID, echoed so a row can be traced back to its listing without the
  /// caller having to remember which listing it asked about.
  final String listingId;

  /// 1..5, guaranteed by the CHECK constraint server-side.
  final int rating;

  /// Optional and possibly empty; the server trims it and caps it at 300.
  final String? comment;

  /// First name plus last initial, e.g. "Maria S.". The backend never sends the
  /// full name, an email or a mobile number, so there is nothing here to filter
  /// out before it is displayed.
  final String reviewer;

  final String? createdAt;
  final String? updatedAt;

  /// Whether this row is the signed-in user's own review.
  ///
  /// Resolved server-side against the bearer token rather than by comparing ids
  /// in the app, so a review cannot be styled as the caller's own by a client
  /// that only got the list.
  final bool isMine;

  const ListingReview({
    required this.id,
    required this.listingId,
    required this.rating,
    this.comment,
    required this.reviewer,
    this.createdAt,
    this.updatedAt,
    this.isMine = false,
  });

  factory ListingReview.fromJson(Map<String, dynamic> json) {
    final rawRating = json['rating'];
    final rawComment = json['comment'];

    return ListingReview(
      id: json['id'] as String? ?? '',
      listingId: json['listing_id'] as String? ?? '',
      // Clamped rather than trusted: a rating outside 1..5 would make the star
      // row loop wrong or draw nothing at all, and the server already refuses
      // to store one.
      rating: rawRating is num ? rawRating.toInt().clamp(1, 5) : 1,
      // An all-whitespace comment is treated as no comment, matching the server,
      // which trims before storing and would otherwise return an empty string.
      comment: (rawComment?.trim().isEmpty ?? true)
          ? null
          : rawComment as String,
      // Treated the same as a missing key: an empty byline would render a row
      // with a blank name, which reads as a rendering fault rather than as a
      // review with no visible reviewer.
      reviewer: (json['reviewer'] as String?)?.trim().isNotEmpty == true
          ? (json['reviewer'] as String).trim()
          : 'A buyer',
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      isMine: json['is_mine'] as bool? ?? false,
    );
  }

  /// Whether the reviewer left words as well as stars, which is what the row
  /// shows a comment block for.
  bool get hasComment => comment != null && comment!.trim().isNotEmpty;

  /// "3 days ago" style label, matching the wording listing cards already use.
  ///
  /// Shared with the listing model rather than duplicated so a review and the
  /// listing it belongs to do not end up saying "today" and "1 day ago" about
  /// the same date.
  String get createdLabel {
    final parsed = DateTime.tryParse(createdAt ?? '');
    if (parsed == null) return '';

    final diff = DateTime.now().difference(parsed);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes;
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    }
    final days = diff.inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1 day ago';
    if (days < 30) return '$days days ago';
    final months = (days / 30).floor();
    return months == 1 ? '1 month ago' : '$months months ago';
  }

  @override
  String toString() =>
      'ListingReview(id: $id, rating: $rating, reviewer: $reviewer)';
}

/// Everything GET /api/listings/{id}/reviews returns in one object.
///
/// Bundled so a widget holds one piece of state and cannot end up showing a
/// summary from one response beside the reviews from another.
class ListingReviewsPage {
  final List<ListingReview> reviews;
  final RatingSummary summary;

  /// The signed-in user's own review, already loaded. Null for a guest, and
  /// null before they have written one. The rate sheet opens filled in from
  /// this instead of starting blank.
  final ListingReview? myReview;

  /// Whether this viewer is allowed to write at all right now.
  final bool canReview;

  /// Why not, as a sentence the app can show verbatim.
  ///
  /// Never null when [canReview] is false and null when it is true, so a
  /// disabled "Write a review" button can always explain itself.
  final String? blockedReason;

  final int currentPage;
  final int lastPage;
  final int total;

  const ListingReviewsPage({
    this.reviews = const [],
    this.summary = const RatingSummary.none(),
    this.myReview,
    this.canReview = false,
    this.blockedReason,
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
  });

  factory ListingReviewsPage.fromJson(Map<String, dynamic> json) {
    final rawReviews = json['reviews'] as List? ?? const [];

    return ListingReviewsPage(
      reviews: rawReviews
          .map((r) => ListingReview.fromJson(r as Map<String, dynamic>))
          .toList(),
      summary: RatingSummary.fromJson(json['summary'] as Map<String, dynamic>?),
      myReview: json['my_review'] == null
          ? null
          : ListingReview.fromJson(json['my_review'] as Map<String, dynamic>),
      canReview: json['can_review'] as bool? ?? false,
      blockedReason: json['review_blocked_reason'] as String?,
      currentPage: (json['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (json['last_page'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Whether there is a further page to fetch.
  bool get hasMorePages => currentPage < lastPage;

  /// Whether this viewer has already reviewed this listing.
  bool get hasMine => myReview != null;

  /// What the "Write a review" button should say for this viewer.
  ///
  /// Editing rather than writing once they have reviewed — the button opens the
  /// same sheet either way, so this only sets the label and the hint.
  String get writeActionLabel =>
      hasMine ? 'Edit your review' : 'Write a review';

  /// Applies a create/update response so the list, the summary and the
  /// prefill state all move together.
  ///
  /// Used after a write instead of re-fetching the page: the endpoint returns
  /// the saved row and the new summary, which is exactly what changed.
  ListingReviewsPage withSavedReview(
    ListingReview review,
    RatingSummary newSummary,
  ) {
    final merged = [
      for (final existing in reviews)
        if (existing.id != review.id) existing,
      review,
    ]..sort(_newestFirst);

    return copyWith(
      reviews: merged,
      summary: newSummary,
      myReview: review,
      total: newSummary.count,
    );
  }

  /// Applies a delete response.
  ///
  /// The row is dropped locally rather than refetched. [newSummary] comes from
  /// the delete response, so the average updates in the same repaint and the
  /// card cannot briefly show a rating for a review that is gone.
  ListingReviewsPage withoutReview(String reviewId, RatingSummary newSummary) {
    return copyWith(
      reviews: reviews.where((r) => r.id != reviewId).toList(growable: false),
      summary: newSummary,
      // Explicit flag rather than a null argument: copyWith treats a null
      // argument as "leave this alone", so passing myReview: null would leave
      // the deleted review in place as the sheet's prefill.
      clearMyReview: myReview?.id == reviewId,
      total: newSummary.count,
    );
  }

  /// Replaces this page's rows when another page arrives, keeping the summary.
  ListingReviewsPage withReviews(List<ListingReview> next) {
    return copyWith(reviews: next, currentPage: currentPage);
  }

  ListingReviewsPage copyWith({
    List<ListingReview>? reviews,
    RatingSummary? summary,
    ListingReview? myReview,
    bool clearMyReview = false,
    bool? canReview,
    String? blockedReason,
    bool clearBlockedReason = false,
    int? currentPage,
    int? lastPage,
    int? total,
  }) {
    return ListingReviewsPage(
      reviews: reviews ?? this.reviews,
      summary: summary ?? this.summary,
      myReview: clearMyReview ? null : (myReview ?? this.myReview),
      canReview: canReview ?? this.canReview,
      blockedReason: clearBlockedReason
          ? null
          : (blockedReason ?? this.blockedReason),
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
    );
  }

  /// Newest first, falling back to the id so two reviews written in the same
  /// millisecond keep a stable order between rebuilds instead of shuffling.
  static int _newestFirst(ListingReview a, ListingReview b) {
    final aDate = DateTime.tryParse(a.createdAt ?? '');
    final bDate = DateTime.tryParse(b.createdAt ?? '');

    if (aDate != null && bDate != null && !aDate.isAtSameMomentAs(bDate)) {
      return bDate.compareTo(aDate);
    }
    return b.id.compareTo(a.id);
  }

  @override
  String toString() =>
      'ListingReviewsPage(${reviews.length} reviews, total: $total, canReview: $canReview)';
}

/// A star rating to submit. Optional comment on the same object so the sheet
/// cannot send a rating with no comment field or the reverse.
class ReviewDraft {
  final int rating;

  /// Not trimmed here: the server trims and enforces the 300 limit, and
  /// duplicating the rule in two places invites the two to disagree.
  final String? comment;

  const ReviewDraft({required this.rating, this.comment});

  Map<String, dynamic> toJson() => {
    'rating': rating,
    if (comment != null && comment!.trim().isNotEmpty)
      'comment': comment!.trim(),
  };

  @override
  String toString() => 'ReviewDraft(rating: $rating)';
}

/// One page of reviews plus how to ask for the next.
///
/// The same type comes back from a read and from a write, because both carry
/// the same thing the UI needs to redraw: the summary. [savedReview] is what
/// distinguishes them — a write response carries the row it just saved, a read
/// does not, and the caller splices that row into its list instead of
/// refetching the page it already has.
class ReviewPageResult {
  final List<ListingReview> reviews;
  final RatingSummary summary;
  final int currentPage;
  final int lastPage;
  final int total;

  /// Set only by create/update responses.
  final ListingReview? savedReview;

  /// The signed-in user's own review and whether they may write at all.
  ///
  /// Carried here rather than read straight out of the JSON at the call site so
  /// the section cannot quietly discard them: the list endpoint is the only
  /// response that sends these, and dropping them leaves the write button
  /// permanently disabled no matter what the server said.
  final ListingReview? myReview;
  final bool canReview;
  final String? blockedReason;

  const ReviewPageResult({
    required this.reviews,
    required this.summary,
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
    this.savedReview,
    this.myReview,
    this.canReview = false,
    this.blockedReason,
  });

  bool get hasMorePages => currentPage < lastPage;
}
