import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/my_farm_listing_page.dart';
import 'auth_service.dart';
import 'listing_service.dart';

/// The seam the My Farm list loads through.
///
/// Exists so widget tests can hand the screen a scripted sequence of pages
/// without a server, which is the only way to test "page 2 is never requested
/// twice" or "a failed page keeps its rows" — both of which are about WHEN a
/// request happens, and neither of which can be observed through real HTTP.
abstract class MyFarmListingsGateway {
  /// One page of listings. Throws on failure; the screen decides what a failure
  /// means for rows it already has.
  Future<MyFarmListingPage> fetch({
    required int page,
    required int perPage,
    required String? farmId,
    required MyFarmStatusFilter status,
  });
}

/// Real implementation: GET /api/my-listings.
class MyFarmListingsService implements MyFarmListingsGateway {
  /// Shared instance, so the screen defaults to the backend and a test passes
  /// its own gateway. Same shape as ReviewService.instance.
  static final MyFarmListingsService instance = MyFarmListingsService();

  /// Files a re-evaluation request for a listing an admin took down.
  ///
  /// Returns a record with a nullable [error] and the server's [message] so the
  /// screen can show the confirmation or the refusal (already pending, previous
  /// denial final, not appealable). Never throws.
  static Future<({String? error, String? message})> requestReEvaluation({
    required String listingId,
    required String reason,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) return (error: 'Not logged in.', message: null);

    try {
      final response = await http.post(
        Uri.parse('${ListingService.baseUrl}/listings/$listingId/appeal'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {'reason': reason.trim()},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return (error: null, message: data['message'] as String?);
      }

      return (
        error: data is Map && data['message'] is String
            ? data['message'] as String
            : 'Could not send the request. Please try again.',
        message: null,
      );
    } catch (_) {
      return (
        error: 'Could not reach the server. Check your connection.',
        message: null,
      );
    }
  }

  @override
  Future<MyFarmListingPage> fetch({
    required int page,
    required int perPage,
    required String? farmId,
    required MyFarmStatusFilter status,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Not logged in.');

    try {
      // Every paging call sends its parameters, because the endpoint only
      // paginates a caller that asks: leaving per_page off would silently ask
      // for the whole list again.
      final uri = Uri.parse('${ListingService.baseUrl}/my-listings').replace(
        queryParameters: {
          'page': '$page',
          'per_page': '$perPage',
          'status': status.wire,
          // The seller's own view of a listing an admin took down. Without
          // this the app cannot show a "Hidden by admin" chip for the one
          // listing that most needs explaining.
          'include_removed': '1',
          if (farmId != null && farmId.isNotEmpty) 'farm_id': farmId,
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return MyFarmListingPage.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      throw Exception('Failed to load your listings.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }
}
