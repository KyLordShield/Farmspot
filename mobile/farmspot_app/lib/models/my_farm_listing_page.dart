import 'listing.dart';

/// Which slice of the farmer's listings the My Farm list is showing.
///
/// The names are the server's `?status` values verbatim, so a filter chip and
/// the request behind it cannot drift apart. [all] is the default and is sent
/// as "all" rather than omitted, so the server's own default is never the
/// thing being tested.
enum MyFarmStatusFilter {
  all('all', 'All'),
  active('active', 'Active'),
  expired('expired', 'Expired'),
  hidden('hidden', 'Hidden by admin'),
  underReview('under_review', 'Under review');

  /// The value sent as `?status=`.
  final String wire;

  /// The chip label. "Hidden by admin" is spelled out rather than shortened to
  /// "Hidden", because "hidden" on its own reads like the farmer chose it.
  final String label;

  const MyFarmStatusFilter(this.wire, this.label);
}

/// Totals for the whole farm, computed on the server.
///
/// Everything here is a count of the FARM, not of the rows that happen to be
/// loaded. A list showing page 2 of Active still says "12 listings" if the
/// farmer has twelve, and counting the loaded rows would say 2 — which is how a
/// summary card starts disagreeing with the thing it summarises.
class MyFarmSummary {
  final int totalListings;
  final int activeCount;
  final int expiredCount;
  final int hiddenCount;
  final int underReviewCount;
  final int reviewCount;

  /// The farm's overall average, or null when nothing has been reviewed.
  ///
  /// Null rather than 0.0 for the same reason a listing's own average is: an
  /// unreviewed farm is not a zero-star one, and "0.0" next to a star reads as
  /// a verdict nobody wrote.
  final double? ratingAverage;

  const MyFarmSummary({
    this.totalListings = 0,
    this.activeCount = 0,
    this.expiredCount = 0,
    this.hiddenCount = 0,
    this.underReviewCount = 0,
    this.reviewCount = 0,
    this.ratingAverage,
  });

  /// Empty before the first response, so the card can render its frame without
  /// inventing numbers.
  static const empty = MyFarmSummary();

  factory MyFarmSummary.fromJson(Map<String, dynamic> json) {
    final average = json['rating_average'];
    return MyFarmSummary(
      totalListings: (json['total_listings'] as num?)?.toInt() ?? 0,
      activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
      expiredCount: (json['expired_count'] as num?)?.toInt() ?? 0,
      hiddenCount: (json['hidden_count'] as num?)?.toInt() ?? 0,
      underReviewCount: (json['under_review_count'] as num?)?.toInt() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      ratingAverage: average == null ? null : (average as num).toDouble(),
    );
  }

  /// The count behind one filter chip.
  int countFor(MyFarmStatusFilter filter) => switch (filter) {
    MyFarmStatusFilter.all => totalListings,
    MyFarmStatusFilter.active => activeCount,
    MyFarmStatusFilter.expired => expiredCount,
    MyFarmStatusFilter.hidden => hiddenCount,
    MyFarmStatusFilter.underReview => underReviewCount,
  };

  MyFarmSummary copyWith({
    int? totalListings,
    int? activeCount,
    int? expiredCount,
    int? hiddenCount,
    int? underReviewCount,
    int? reviewCount,
    double? ratingAverage,
  }) {
    return MyFarmSummary(
      totalListings: totalListings ?? this.totalListings,
      activeCount: activeCount ?? this.activeCount,
      expiredCount: expiredCount ?? this.expiredCount,
      hiddenCount: hiddenCount ?? this.hiddenCount,
      underReviewCount: underReviewCount ?? this.underReviewCount,
      reviewCount: reviewCount ?? this.reviewCount,
      ratingAverage: ratingAverage ?? this.ratingAverage,
    );
  }
}

/// One page of the farmer's listings plus the farm-wide totals.
class MyFarmListingPage {
  final List<Listing> listings;

  /// 1-based. [lastPage] is never below 1, so the screen can compare against it
  /// without guarding for an empty result set reporting zero pages.
  final int currentPage;
  final int lastPage;

  /// Every listing in scope, across every page. This is the number a seller
  /// means by "my listings" and it is deliberately not the row count.
  final int total;
  final MyFarmSummary summary;

  const MyFarmListingPage({
    this.listings = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
    this.summary = MyFarmSummary.empty,
  });

  bool get hasMore => currentPage < lastPage;

  factory MyFarmListingPage.fromJson(Map<String, dynamic> json) {
    final rows = (json['listings'] as List? ?? const [])
        .map((row) => Listing.fromJson(row as Map<String, dynamic>))
        .toList();

    final pagination = json['pagination'] as Map<String, dynamic>?;

    return MyFarmListingPage(
      listings: rows,
      // An unpaged response has no pagination block, so it is one complete
      // page. That keeps "is there more?" answerable against a server that
      // predates paging rather than defaulting to "yes, forever".
      currentPage: (pagination?['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (pagination?['last_page'] as num?)?.toInt() ?? 1,
      total: (pagination?['total'] as num?)?.toInt() ?? rows.length,
      summary: json['summary'] is Map<String, dynamic>
          ? MyFarmSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : MyFarmSummary.empty,
    );
  }
}

/// Everything the server says about one listing as far as the OWNER is
/// concerned: the state a buyer never sees.
class ListingOwnerState {
  final Listing listing;

  /// LST_AVAILABILITY as a moderation verdict: REMOVED, or NOT_AVAILABLE when
  /// an admin set it.
  ///
  /// NOT_AVAILABLE is also a value a farmer can choose for LST_STATUS, which is
  /// a different column entirely — a farmer saying "this crop is gone" is not
  /// the same as us taking it off sale, and the chip only appears for the
  /// second one.
  final bool hiddenByAdmin;

  /// An open report exists. The seller is told the Association is looking and
  /// nothing else: no reporter, no reason, no details.
  ///
  /// Read off the listing rather than stored twice, so there is no way for the
  /// row and its chip to disagree about whether a report is open.
  bool get underReview => listing.hasOpenReport;

  const ListingOwnerState({required this.listing, this.hiddenByAdmin = false});

  /// LST_EXPIRY_DATE in the past, which is what `listings:expire` acts on.
  bool get isExpired {
    final raw = listing.expiryDate;
    if (raw == null || raw.isEmpty) return false;
    final expiry = DateTime.tryParse(raw);
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  /// True while the listing is still inside its 3-day window.
  bool get hasExpiryCountdown => !isExpired && listing.expiryDate != null;

  /// "Expires in 2 days", "Expires today", or null when the date is missing or
  /// already past — an expired listing shows the red Expired chip instead, and a
  /// countdown on top of that would say "in -1 days".
  String? get expiryLabel {
    if (!hasExpiryCountdown) return null;
    final expiry = DateTime.tryParse(listing.expiryDate!);
    if (expiry == null) return null;

    // DateTime, not Duration: "Expires in 2 days" has to stay true at 11pm on
    // the day before, and a 47-hour remainder rounds to 1 day, not 2.
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfExpiry = DateTime(expiry.year, expiry.month, expiry.day);
    final days = startOfExpiry.difference(startOfToday).inDays;

    if (days <= 0) return 'Expires today';
    if (days == 1) return 'Expires in 1 day';
    return 'Expires in $days days';
  }
}
