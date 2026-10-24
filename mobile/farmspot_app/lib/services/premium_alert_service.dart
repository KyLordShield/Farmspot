import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/premium_alert_settings.dart';
import 'api_config.dart';
import 'auth_service.dart';

abstract class PremiumAlertsGateway {
  Future<PremiumAlertSettings> fetchSettings();
  Future<PremiumAlertSettings> saveSettings(PremiumAlertSettings settings);
}

class PremiumAlertService implements PremiumAlertsGateway {
  final http.Client _client;
  PremiumAlertService({http.Client? client})
    : _client = client ?? http.Client();
  static final instance = PremiumAlertService();
  @override
  Future<PremiumAlertSettings> fetchSettings() async =>
      PremiumAlertSettings.fromJson(
        await _request('GET', '/premium/alert-settings'),
      );
  @override
  Future<PremiumAlertSettings> saveSettings(
    PremiumAlertSettings settings,
  ) async => PremiumAlertSettings.fromJson(
    await _request('PUT', '/premium/alert-settings', settings.toJson()),
  );
  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Please sign in to use alert settings.');
    final request =
        http.Request(method, Uri.parse('${ApiConfig.apiBaseUrl}$path'))
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception(
        'The request timed out. Refresh alert settings to check the result.',
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }
    if (await AuthService.getToken() != token)
      throw Exception('Your account changed. Please try again.');
    if (response.statusCode == 401) {
      await AuthService.expireSession();
      throw Exception('Please sign in again.');
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The server sent an unexpected response.');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw Exception(
      data['message'] as String? ?? 'Could not save alert settings.',
    );
  }
}
