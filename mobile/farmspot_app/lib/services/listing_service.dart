import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/listing.dart';

class ListingService {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  /// Fetches the browse feed. Returns the list on success, or throws
  /// an Exception with a user-friendly message on failure.
  static Future<List<Listing>> fetchListings({String? search}) async {
    try {
      final uri = Uri.parse('$baseUrl/listings').replace(
        queryParameters: (search != null && search.trim().isNotEmpty)
            ? {'search': search.trim()}
            : null,
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final listings = data['listings'] as List;
        return listings
            .map((json) => Listing.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Failed to load listings.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  /// Fetches a single listing's detail by ID.
  static Future<Listing> fetchListing(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/listings/$id'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Listing.fromJson(data['listing'] as Map<String, dynamic>);
      }

      throw Exception('Listing not found.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }
}