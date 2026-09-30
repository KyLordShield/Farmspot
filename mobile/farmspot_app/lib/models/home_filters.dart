/// How the home feed is ordered, and what the Filter button lets a buyer
/// narrow it by.
///
/// This is the one place the three filter groups live. The sheet edits a
/// [HomeFilters] value, the button reads [HomeFilters.isActive] and
/// [HomeFilters.summaryFor] to decide how to look, and ListingService turns the
/// same value into query params. Keeping one value object means the button
/// cannot disagree with the request it is about to make.
library;

/// The ordering options offered in the filter sheet.
///
/// [wireValue] is what goes into `?sort=`. `latest` is deliberately not sent
/// at all (see ListingService) because it is the backend's default, and
/// sending it would put a redundant param on the most frequent request in the
/// app.
enum HomeSortMode {
  /// Newest listing first. The default, and the order the feed already used.
  latest('latest', 'Latest'),

  /// Soonest expected harvest first. Listings with no harvest date set sink to
  /// the bottom rather than leading the feed, which is why this is a real
  /// second ordering and not a duplicate of [latest].
  date('date', 'By harvest date'),

  /// Most contacted first. There is no view counter in the schema, so
  /// "contacted" — a buyer tapped call or SMS on that listing — is the honest
  /// popularity signal.
  popular('popular', 'Most popular');

  const HomeSortMode(this.wireValue, this.label);

  /// The value the backend's `?sort=` whitelist expects.
  final String wireValue;

  /// What the sheet shows.
  final String label;
}

/// The availability groups a buyer can filter by.
///
/// These map onto `listing.LST_STATUS`. `NOT_AVAILABLE` is absent on purpose:
/// the public feed already excludes it, and `listings:expire` moves every
/// past-due row into it, so offering it would show an empty list.
enum FeedAvailability {
  availableNow('AVAILABLE_NOW', 'Available now'),
  soonToHarvest('SOON_TO_HARVEST', 'Soon to harvest');

  const FeedAvailability(this.wireValue, this.label);

  /// The value sent as `?status=`.
  final String wireValue;

  /// What the sheet shows.
  final String label;
}

/// The full filter state of the home feed.
///
/// Immutable so it can be compared directly to decide whether the feed needs
/// reloading, and so a dismissed sheet cannot leave a half-applied filter
/// behind: the sheet edits a local copy and the screen only adopts it on
/// "Apply".
class HomeFilters {
  /// A crop category id (`LEAFVG`, `ROOTCP`, ...), or null for every category.
  final String? categoryId;

  /// An availability group, or null for both.
  final FeedAvailability? availability;

  /// How to order the feed.
  final HomeSortMode sort;

  const HomeFilters({
    this.categoryId,
    this.availability,
    this.sort = HomeSortMode.latest,
  });

  /// Nothing filtered, newest first. The state the home feed starts in.
  static const HomeFilters none = HomeFilters();

  /// Whether anything would change the request. The Filter button uses this to
  /// decide between its quiet and its active appearance, so "show me popular"
  /// is visibly different from the default even though only the order moved.
  bool get isActive =>
      categoryId != null || availability != null || sort != HomeSortMode.latest;

  /// Whether the *server* has to be asked again.
  ///
  /// Availability and sort go to the backend as query params. Category does
  /// NOT: the feed already holds every listing the backend returned, so
  /// sending `?category=` as well would filter the same set twice over.
  /// Keeping category local is what lets applying it return immediately —
  /// no spinner, no round trip.
  bool get needsRefetch => availability != null;

  /// Whether the shown set of listings changes, ignoring order.
  ///
  /// Re-sorting does not change which listings are shown, so [HomeScreen] can
  /// reorder the list it already has without a round trip. Narrowing does, so
  /// that still refetches.
  bool get narrowsResultSet => categoryId != null || availability != null;

  /// A short "what is applied" line for the Filter button.
  ///
  /// [categoryName] resolves [categoryId] to something readable. It is passed
  /// in rather than stored because the name comes from the category list the
  /// screen already holds, and baking it into this value would make two
  /// HomeFilters that differ only by name compare unequal — which would make
  /// an untouched sheet look changed and trigger a pointless reload.
  ///
  /// Returns null when nothing is applied, so the button can fall back to its
  /// own label rather than printing an empty string.
  String? summaryFor({String? categoryName}) {
    final parts = <String>[];
    if (categoryId != null) parts.add(categoryName ?? '1 category');
    if (availability != null) parts.add(availability!.label);
    if (sort != HomeSortMode.latest) parts.add(sort.label);
    if (parts.isEmpty) return null;
    return parts.join(' • ');
  }

  HomeFilters copyWith({
    String? categoryId,
    bool clearCategory = false,
    FeedAvailability? availability,
    bool clearAvailability = false,
    HomeSortMode? sort,
  }) {
    return HomeFilters(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      availability: clearAvailability
          ? null
          : (availability ?? this.availability),
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeFilters &&
      other.categoryId == categoryId &&
      other.availability == availability &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(categoryId, availability, sort);

  @override
  String toString() =>
      'HomeFilters(category: $categoryId, availability: $availability, '
      'sort: ${sort.wireValue})';
}
