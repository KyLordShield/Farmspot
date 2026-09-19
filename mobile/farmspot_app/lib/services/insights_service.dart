import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/insights.dart';

class InsightsService {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  /// Fetches the Insights dashboard payload (GET /api/insights). Public
  /// endpoint — no auth token needed. Returns the parsed payload on success,
  /// or throws an Exception with a user-friendly message on failure.
  static Future<InsightsPayload> fetchInsights() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/insights'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return InsightsPayload.fromJson(data as Map<String, dynamic>);
      }

      throw Exception('Failed to load crop insights.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }
}