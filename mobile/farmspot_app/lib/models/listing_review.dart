/// One file for both the wire shapes the reviews endpoint returns: the
/// `{average, count}` block and a single review row. They are always used
/// together — a listing's reviews are not shown without the summary above them,
/// and the summary is not shown without the list — so keeping them adjacent
/// keeps the null-handling rules in one place.
///
/// The null handling is the whole point of this file. The backend sends
/// `average: null` for a listing nobody has reviewed, and `null` must never
/// become 0: showing "0.0" or an empty star row on a brand new listing claims
/// buyers already judged it badly. [RatingSummary.hasRatings] is what gates
/// every render.
library;

/// How the "See all reviews" list is ordered.
///
/// The wire values match the server's `sort` parameter exactly. [ReviewSort.newest]
/// is the default and is what the endpoint already did, so a screen that never
/// touches the selector sends no parameter and changes nothing.
enum ReviewSort {
  newest('newest', 'Newest'),
  best('best', 'Best'),
  highest('highest', 'Highest'),
  lowest('lowest', 'Lowest');

  const ReviewSort(this.wireValue, this.label);

  /// What goes in `?sort=`.
  final String wireValue;

  /// What the selector shows.
  final String label;

  /// Parses a wire value, falling back to [ReviewSort.newest].
  ///
  /// Never throws: an unknown value from a newer server must not blank a list
  /// the buyer is reading.
  static ReviewSort fromWire(String? value) {
    for (final option in ReviewSort.values) {
      if (option.wireValue == value) return option;
    }
    return ReviewSort.newest;
  }
}

/// The whole selection behind the See all screen's chips and selector.
///
/// One object rather than two loose fields because the star chips are
/// single-select while "With comments" combines with them: keeping the pair in
/// one immutable value is what stops the two from drifting into a state the
/// screen cannot represent, and makes "changing anything resets to page 1" a
/// single comparison in the widget.
///
/// The combination travels as two independent parameters, `rating` and
/// `with_comment`, so the backend never has to understand a combined token. A
/// null [rating] means "all ratings", which is an absent parameter rather than
/// `rating=0`, because the endpoint rejects an out-of-range value outright.
class ReviewFilter {
  /// Selected star count, or null for All.
  final int? rating;

  /// Whether "With comments" is on.
  final bool withCommentsOnly;

  const ReviewFilter({this.rating, this.withCommentsOnly = false});

  const ReviewFilter.all() : rating = null, withCommentsOnly = false;

  /// Whether anything at all is being filtered, which decides between the
  /// "No reviews yet" and "No reviews match this filter" empty states.
  bool get isActive => rating != null || withCommentsOnly;

  /// Selects one star band, replacing any previous star selection.
  ReviewFilter withRating(int? value) =>
      ReviewFilter(rating: value, withCommentsOnly: withCommentsOnly);

  /// Toggles "With comments", leaving the star selection alone.
  ReviewFilter withComments(bool value) =>
      ReviewFilter(rating: rating, withCommentsOnly: value);

  ReviewFilter copyWith({int? rating, bool? withCommentsOnly}) {
    return ReviewFilter(
      rating: rating ?? this.rating,
      withCommentsOnly: withCommentsOnly ?? this.withCommentsOnly,
    );
  }

  /// The query parameters this filter adds, omitted when they would be no-ops.
  ///
  /// [ReviewSort.newest] is excluded because it is the endpoint's existing
  /// default, and [withCommentsOnly] false is excluded because an explicit
  /// `with_comment=false` would narrow the list to bare star ratings, which is
  /// not what an untouched screen means.
  Map<String, String> toQuery({ReviewSort sort = ReviewSort.newest}) {
    return {
      if (sort != ReviewSort.newest) 'sort': sort.wireValue,
      if (rating != null) 'rating': '$rating',
      if (withCommentsOnly) 'with_comment': 'true',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReviewFilter &&
      other.rating == rating &&
      other.withCommentsOnly == withCommentsOnly;

  @override
  int get hashCode => Object.hash(rating, withCommentsOnly);

  @override
  String toString() =>
      'ReviewFilter(rating: $rating, withComments: $withCommentsOnly)';
}

/// `{average, count}` from GET /api/listings/{id}/reviews, and the
/// `rating_average` / `rating_count` pair on a listing payload.
class RatingSummary {
  /// Mean of the visible review ratings, or null when there are none.
  final double? average;

  /// How many visible reviews the average is over.
  final int count;

  /// Counts per rating, 1 to 5, over every visible review.
  ///
  /// New on the API as `rating_breakdown`. Always all five entries, zeros
  /// included, so the filter chips never have to guard a missing index to
  /// decide whether to print a count. Never affected by an active filter: the
  /// numbers beside the chips describe the listing, not the current selection.
  final Map<int, int> ratingBreakdown;

  const RatingSummary({
    this.average,
    this.count = 0,
    this.ratingBreakdown = const {},
  });

  const RatingSummary.none()
      : average = null,
        count = 0,
        ratingBreakdown = const {};

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
      ratingBreakdown: breakdownFromJson(json['rating_breakdown']),
    );
  }

  /// How many visible reviews carry [rating] stars, 0 when unknown.
  ///
  /// Returns 0 rather than throwing when the server omitted the breakdown, so
  /// an older backend still renders chips without counts.
  int countFor(int rating) => ratingBreakdown[rating] ?? 0;

  /// Whether the server sent a usable breakdown, so chips can show counts.
  bool get hasBreakdown => ratingBreakdown.isNotEmpty;

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
      // Carried over rather than defaulted: the breakdown arrives on the same
      // response as the average, and dropping it here would blank every chip
      // count the moment a buyer saved or deleted a review.
      ratingBreakdown: ratingBreakdown,
    );
  }

  @override
  String toString() => 'RatingSummary(average: $average, count: $count)';
}

/// Reads `rating_breakdown` into a {1..5: count} map.
///
/// Shared by the summary block and the listing payload. JSON object keys are
/// strings, so "5" has to be read as a key and the value taken with it; keys
/// that are not 1..5 are dropped rather than clamped, since a clamped entry
/// would silently overstate one star band.
Map<int, int> breakdownFromJson(Object? raw) {
  if (raw is! Map) return const {};

  final breakdown = <int, int>{};

  for (final entry in raw.entries) {
    final rating = int.tryParse(entry.key.toString());
    final total = entry.value;

    if (rating == null || rating < 1 || rating > 5) continue;
    if (total is! num) continue;

    breakdown[rating] = total.toInt();
  }

  return breakdown;
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

  /// Whether the caller's own row is among the rows currently loaded.
  ///
  /// Not the same question as [hasMine]: the own review exists either way, but
  /// it may be on a page nobody has scrolled to, or excluded by an active
  /// filter. The See all screen uses this to decide whether to pin a "Your
  /// review" row above the list so the edit and delete buttons stay reachable.
  bool get listsMine =>
      myReview != null && reviews.any((review) => review.id == myReview!.id);

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
