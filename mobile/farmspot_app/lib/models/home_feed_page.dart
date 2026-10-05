import 'listing.dart';

/// One page of the home feed, plus what the server said about the rest of it.
///
/// A page is a value rather than a bare list because the feed needs three
/// things from one response: the rows, whether there are more, and which page
/// they were. Returning a plain list would force the screen to either guess
/// (stop when a page is short, which silently loses the tail when the last page
/// happens to be full) or count what it already has, which is a different
/// number from the server's on every request that filters.
class HomeFeedPage {
  /// The listings in this page, already in the order the server ranked them.
  final List<Listing> listings;

  /// Which page this is, as the server numbered it.
  final int currentPage;

  /// The last page that exists. Always at least 1, so an empty feed reports
  /// `currentPage == lastPage` and "has more" is simply false.
  final int lastPage;

  /// How many listings the server is paging over.
  final int total;

  const HomeFeedPage({
    required this.listings,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  /// Whether asking for the next page can return anything.
  bool get hasMore => currentPage < lastPage;

  /// A whole feed expressed as a single page.
  ///
  /// Used when the server answers without pagination metadata — an older
  /// backend, or a route that has not opted in. Everything arrived, so there is
  /// provably nothing more to fetch, and claiming `lastPage == currentPage` is
  /// what stops the screen asking again forever.
  factory HomeFeedPage.unpaged(List<Listing> listings) => HomeFeedPage(
    listings: listings,
    currentPage: 1,
    lastPage: 1,
    total: listings.length,
  );
}
