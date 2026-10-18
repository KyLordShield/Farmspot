import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/search_suggestions.dart';
import '../models/user_profile.dart';
import 'api_config.dart';

/// Buyer-facing search data that is not the plain listing feed.
///
/// The crop grid itself still comes from `ListingService` (GET /api/listings),
/// which owns the search_log insert. This service covers the two new surfaces:
/// the combined crop/farm/seller probe (GET /api/search) and a seller profile
/// (GET /api/sellers/{id}).
class SearchService {
  static final String baseUrl = ApiConfig.apiBaseUrl;

  /// Combined crop + farm + seller matches for one term (GET /api/search).
  ///
  /// Best-effort by design: the endpoint is hit on every debounced keystroke, so
  /// any failure returns [SearchSuggestions.empty] rather than throwing — typing
  /// must never surface an error, and the buyer can always submit for real
  /// results.
  static Future<SearchSuggestions> fetchSearch(
    String term, {
    int limit = 8,
  }) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return SearchSuggestions.empty;

    try {
      final uri = Uri.parse('$baseUrl/search').replace(
        queryParameters: {'q': trimmed, 'limit': '$limit'},
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return SearchSuggestions.empty;

      final data = jsonDecode(response.body);
      if (data is! Map) return SearchSuggestions.empty;

      return SearchSuggestions.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return SearchSuggestions.empty;
    }
  }

  /// One person's public profile (GET /api/users/{userId}/profile).
  ///
  /// Throws an Exception carrying a user-friendly message on failure so the
  /// screen can show its retry state, matching the rest of the app's services.
  static Future<UserProfile> fetchUserProfile(String userId) async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse('$baseUrl/users/$userId/profile'),
        headers: {'Accept': 'application/json'},
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 404) {
      throw Exception('This profile is no longer available.');
    }
    if (response.statusCode != 200) {
      throw Exception('Could not load this profile.');
    }

    final data = jsonDecode(response.body);
    if (data is! Map) {
      throw Exception('Could not load this profile.');
    }

    return UserProfile.fromJson(Map<String, dynamic>.from(data));
  }
}
