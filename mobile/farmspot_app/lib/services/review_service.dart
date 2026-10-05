import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/listing_review.dart';
import 'auth_service.dart';

/// The review calls a screen makes. An interface, for the same reason
/// `MessagesGateway` and `ReportsGateway` are ones: a widget test hands the
/// product detail screen a recording fake instead of standing up a server.
abstract class ReviewsGateway {
  /// One page of a listing's reviews plus its summary.
  ///
  /// [sort], [rating] and [withCommentsOnly] are additive and all default to
  /// what the endpoint did before any of them existed: newest first, unfiltered.
  /// They are omitted from the query string when unset rather than sent empty,
  /// so the default call is byte-identical to the original request.
  Future<ReviewPageResult> fetch({
    required String listingId,
    int page = 1,
    int perPage = 5,
    ReviewSort sort = ReviewSort.newest,
    int? rating,
    bool withCommentsOnly = false,
  });

  /// Creates or updates the signed-in user's review. The backend turns a second
  /// submission into an update, so this is also "edit".
  ///
  /// Throws with a user-readable message on rejection — the sheet shows the
  /// text as-is, so it should be worth showing. In particular the server's
  /// per-rule wording ("This is your own listing.") reaches the user rather
  /// than being replaced by a generic failure.
  Future<ReviewPageResult> save({
    required String listingId,
    required ReviewDraft draft,
  });

  /// Deletes the signed-in user's own review. Throws if there was nothing to
  /// delete.
  Future<ReviewPageResult> delete(String listingId);
}

/// Talks to the Laravel backend's /api/listings/{id}/reviews.
class ReviewService implements ReviewsGateway {
  static const String baseUrl = AuthService.baseUrl;

  /// Shared instance, so screens default to the real backend while tests pass
  /// their own implementation.
  static final ReviewService instance = ReviewService();

  @override
  Future<ReviewPageResult> fetch({
    required String listingId,
    int page = 1,
    int perPage = 5,
    ReviewSort sort = ReviewSort.newest,
    int? rating,
    bool withCommentsOnly = false,
  }) async {
    // page and per_page always go out because pagination needs them. The three
    // narrowing parameters are added only when they are doing something, so the
    // default call sends exactly what it sent before any of this existed.
    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (sort != ReviewSort.newest) 'sort': sort.wireValue,
      if (rating != null) 'rating': '$rating',
      if (withCommentsOnly) 'with_comment': 'true',
    };

    final uri = Uri.parse(
      '$baseUrl/listings/$listingId/reviews',
    ).replace(queryParameters: query);

    final http.Response response;
    try {
      response = await http.get(uri, headers: await _headers());
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    final body = _decode(response);

    if (response.statusCode == 200) {
      return _toPage(body);
    }

    throw Exception((body['message'] as String?) ?? 'Could not load reviews.');
  }

  @override
  Future<ReviewPageResult> save({
    required String listingId,
    required ReviewDraft draft,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/listings/$listingId/reviews'),
        headers: await _headers(),
        body: jsonEncode(draft.toJson()),
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    final body = _decode(response);

    // 201 is a new review, 200 is an update of the existing one. Both are
    // success, and the caller shows different copy for each.
    if (response.statusCode == 201 || response.statusCode == 200) {
      return _toPage(body);
    }

    // 403 is a rule the user hit, not a fault, and the server's wording is
    // per-rule — "This is your own listing.", "Sign in to write a review." —
    // so surface it rather than replacing it.
    if (response.statusCode == 401) {
      throw Exception('Please sign in to write a review.');
    }

    final errors = body['errors'] as Map?;
    if (errors != null && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) {
        throw Exception(first.first.toString());
      }
    }

    throw Exception(
      (body['message'] as String?) ?? 'Could not send your review.',
    );
  }

  @override
  Future<ReviewPageResult> delete(String listingId) async {
    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$baseUrl/listings/$listingId/reviews'),
        headers: await _headers(),
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    final body = _decode(response);

    if (response.statusCode == 200) {
      return _toPage(body);
    }

    throw Exception(
      (body['message'] as String?) ?? 'Could not delete your review.',
    );
  }

  /// Reads whichever shape came back — the list endpoint, or a write response
  /// that carries the saved row and a fresh summary.
  ///
  /// The write responses have no `reviews` array, so a save returns an empty
  /// list plus [ReviewPageResult.savedReview] and the caller splices that row
  /// into the list it already holds rather than refetching.
  ReviewPageResult _toPage(Map<String, dynamic> body) {
    final summary = RatingSummary.fromJson(
      body['summary'] as Map<String, dynamic>?,
    );
    final rawReviews = body['reviews'] as List?;
    final rawSaved = body['review'];

    return ReviewPageResult(
      reviews: rawReviews == null
          ? const []
          : rawReviews
                .map((r) => ListingReview.fromJson(r as Map<String, dynamic>))
                .toList(),
      summary: summary,
      currentPage: (body['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (body['last_page'] as num?)?.toInt() ?? 1,
      total: (body['total'] as num?)?.toInt() ?? summary.count,
      savedReview: rawSaved == null
          ? null
          : ListingReview.fromJson(rawSaved as Map<String, dynamic>),
      // Present on the list endpoint. A write response omits them, which is
      // correct: having just written a review, the caller already knows it may.
      myReview: body['my_review'] == null
          ? null
          : ListingReview.fromJson(body['my_review'] as Map<String, dynamic>),
      canReview: body['can_review'] as bool? ?? false,
      blockedReason: body['review_blocked_reason'] as String?,
    );
  }

  Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      // Attached when there is one, omitted when there is not. The read
      // endpoint is public: a guest still gets the list and the summary, just
      // without my_review and with can_review false.
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The server sent an unexpected response.');
    }
  }
}
