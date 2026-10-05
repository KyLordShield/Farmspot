import '../models/home_feed_page.dart';
import '../models/home_filters.dart';
import 'listing_service.dart';

/// The home feed's data source, as an interface.
///
/// [HomeScreen] takes one of these rather than calling [ListingService]
/// directly, for the same reason My Farm has its own gateway: paging is the
/// screen's job, not the transport's, and the thing worth testing is what the
/// screen does when page one is slow, when page two repeats a listing, and when
/// the third page fails. None of that is reachable without being able to
/// stand a fake in front of it — a static HTTP client can only answer "what
/// does one page look like", which is the least interesting question here.
abstract class HomeFeedGateway {
  /// Fetches one page of the feed.
  ///
  /// [page] is 1-based. Implementations should honour [category],
  /// [availability] and [sort] exactly as passed and throw on failure rather
  /// than returning an empty page, so the screen can tell "no more crops" apart
  /// from "the request failed".
  Future<HomeFeedPage> fetchFeedPage({
    required int page,
    required int perPage,
    String? search,
    String? category,
    String? availability,
    HomeSortMode sort,
    bool personalized,
  });
}

/// The real gateway: [ListingService] over HTTP.
class ListingFeedGateway implements HomeFeedGateway {
  const ListingFeedGateway();

  @override
  Future<HomeFeedPage> fetchFeedPage({
    required int page,
    required int perPage,
    String? search,
    String? category,
    String? availability,
    HomeSortMode sort = HomeSortMode.latest,
    bool personalized = true,
  }) {
    return ListingService.fetchListingsPage(
      page: page,
      perPage: perPage,
      search: search,
      category: category,
      availability: availability,
      sort: sort,
      personalized: personalized,
    );
  }
}
