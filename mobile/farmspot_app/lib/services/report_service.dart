import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/report.dart';
import 'auth_service.dart';

/// The reporting calls the screens need. An interface, for the same reason
/// `MessagesGateway` is one: a widget test can hand a screen a recording fake
/// instead of standing up a server.
abstract class ReportsGateway {
  /// Files one report. Throws with a user-readable message on rejection —
  /// the sheet shows the text as-is, so it should be something worth showing.
  ///
  /// A report that was already filed returns a receipt with
  /// [ReportReceipt.duplicate] set rather than throwing: the user's complaint
  /// did land, and telling them it failed would be a lie.
  Future<ReportReceipt> submit(ReportDraft draft);
}

/// Talks to the Laravel backend's POST /api/reports.
class ReportService implements ReportsGateway {
  static const String baseUrl = AuthService.baseUrl;

  /// Shared instance, so screens default to the real backend while tests pass
  /// their own implementation.
  static final ReportService instance = ReportService();

  @override
  Future<ReportReceipt> submit(ReportDraft draft) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/reports'),
        headers: await _headers(),
        body: jsonEncode(draft.toJson()),
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    final body = _decode(response);
    final report = body['report'] as Map<String, dynamic>?;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ReportReceipt.fromJson(
        report ?? const {},
        // 200 is the server's "already reported within the last day" answer;
        // 201 is a brand new report. Both are success.
        duplicate: response.statusCode == 200,
      );
    }

    // 403 is a rule the user hit rather than a fault, and the server's wording
    // is per-target ("This is your own listing."), so surface it instead of
    // replacing it with a generic failure.
    if (response.statusCode == 429) {
      throw Exception('You have reported a lot recently. Please wait a minute.');
    }

    final errors = body['errors'] as Map?;
    if (errors != null && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) {
        throw Exception(first.first.toString());
      }
    }

    throw Exception((body['message'] as String?) ?? 'Could not send your report.');
  }

  Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
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
