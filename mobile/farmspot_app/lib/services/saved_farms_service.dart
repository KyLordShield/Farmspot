import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/saved_farm.dart';
import 'api_config.dart';
import 'auth_service.dart';

abstract class SavedFarmsGateway {
  Future<List<SavedFarm>> fetchSavedFarms();
  Future<SavedFarm> saveFarm(String id);
  Future<void> removeFarm(String id);
}

class SavedFarmsService implements SavedFarmsGateway {
  final http.Client _client;
  SavedFarmsService({http.Client? client}) : _client = client ?? http.Client();
  static final instance = SavedFarmsService();
  @override
  Future<List<SavedFarm>> fetchSavedFarms() async =>
      ((await _request('GET', '/saved-farms'))['farms'] as List)
          .map((f) => SavedFarm.fromJson(f as Map<String, dynamic>))
          .toList();
  @override
  Future<SavedFarm> saveFarm(String id) async => SavedFarm.fromJson(
    (await _request('PUT', '/saved-farms/$id'))['farm'] as Map<String, dynamic>,
  );
  @override
  Future<void> removeFarm(String id) async {
    await _request('DELETE', '/saved-farms/$id');
  }

  Future<Map<String, dynamic>> _request(String method, String path) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Please sign in to use Saved Farms.');
    final request =
        http.Request(method, Uri.parse('${ApiConfig.apiBaseUrl}$path'))
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          });
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception(
        'The request timed out. Refresh Saved Farms to check the result.',
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
      data['message'] as String? ?? 'Could not update Saved Farms.',
    );
  }
}
