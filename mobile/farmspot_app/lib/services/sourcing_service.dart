import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/sourcing.dart';
import 'api_config.dart';
import 'auth_service.dart';

abstract class SourcingGateway {
  Future<SourcingList> fetchList();
  Future<void> saveList(List<String> crops);
  Future<SourcingMatches> fetchMatches({LatLng? position});
}

class SourcingService implements SourcingGateway {
  final http.Client _client;
  SourcingService({http.Client? client}) : _client = client ?? http.Client();
  static final instance = SourcingService();
  @override
  Future<SourcingList> fetchList() async =>
      SourcingList.fromJson(await _request('GET', '/sourcing/list'));
  @override
  Future<void> saveList(List<String> crops) async {
    await _request('PUT', '/sourcing/list', {'crops': crops});
  }

  @override
  Future<SourcingMatches> fetchMatches({LatLng? position}) async =>
      SourcingMatches.fromJson(
        await _request('POST', '/sourcing/matches', {
          if (position != null) 'latitude': position.latitude,
          if (position != null) 'longitude': position.longitude,
        }),
      );
  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await AuthService.getToken();
    if (token == null)
      throw Exception('Please sign in to use Weekly Sourcing.');
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
        'The request timed out. Refresh Weekly Sourcing to check the result.',
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
      data['message'] as String? ?? 'Could not load Weekly Sourcing.',
    );
  }
}
