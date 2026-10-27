import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/buy_request.dart';
import '../models/crop_choice.dart';
import '../models/conversation.dart';
import 'api_config.dart';
import 'auth_service.dart';

abstract class BuyRequestsGateway {
  Future<List<CropChoice>> fetchCrops();
  Future<List<BuyRequest>> fetchMine();
  Future<List<BuyRequest>> fetchBoard({String? search});
  Future<BuyRequest> create({
    required String crop,
    required double quantityKg,
    required String frequency,
    String? note,
    String? pickupLocation,
    double? latitude,
    double? longitude,
  });
  Future<BuyRequest> update({
    required String id,
    required String crop,
    required double quantityKg,
    required String frequency,
    String? note,
    String? pickupLocation,
    double? latitude,
    double? longitude,
  });
  Future<void> remove(String id);
  Future<Conversation> contactBuyer(String id);
  Future<List<Conversation>> fetchResponses(String id);
}

class BuyRequestService implements BuyRequestsGateway {
  BuyRequestService({http.Client? client}) : _client = client ?? http.Client();
  static final instance = BuyRequestService();
  final http.Client _client;

  @override
  Future<List<CropChoice>> fetchCrops() async =>
      ((await _request('GET', '/buy-request-crops'))['crops'] as List)
          .map((c) => CropChoice.fromJson(c as Map<String, dynamic>))
          .toList();

  @override
  Future<List<BuyRequest>> fetchMine() async =>
      _rows(await _request('GET', '/buy-requests/mine'));
  @override
  Future<List<BuyRequest>> fetchBoard({String? search}) async =>
      _rows(await _request('GET', '/buy-requests', search: search));
  List<BuyRequest> _rows(Map<String, dynamic> data) =>
      (data['requests'] as List)
          .map((r) => BuyRequest.fromJson(r as Map<String, dynamic>))
          .toList();
  @override
  Future<BuyRequest> create({
    required String crop,
    required double quantityKg,
    required String frequency,
    String? note,
    String? pickupLocation,
    double? latitude,
    double? longitude,
  }) async {
    final data = await _request(
      'POST',
      '/buy-requests',
      body: {
        'crop': crop,
        'quantity_kg': quantityKg,
        'frequency': frequency,
        'note': note,
        'pickup_location': pickupLocation,
        if (latitude != null && longitude != null) ...{
          'latitude': latitude,
          'longitude': longitude,
        },
      },
    );
    return BuyRequest.fromJson(data['request'] as Map<String, dynamic>);
  }

  @override
  Future<BuyRequest> update({
    required String id,
    required String crop,
    required double quantityKg,
    required String frequency,
    String? note,
    String? pickupLocation,
    double? latitude,
    double? longitude,
  }) async {
    final data = await _request(
      'PATCH',
      '/buy-requests/$id',
      body: {
        'crop': crop,
        'quantity_kg': quantityKg,
        'frequency': frequency,
        'note': note,
        'pickup_location': pickupLocation,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return BuyRequest.fromJson(data['request'] as Map<String, dynamic>);
  }

  @override
  Future<void> remove(String id) async {
    await _request('DELETE', '/buy-requests/$id');
  }

  @override
  Future<Conversation> contactBuyer(String id) async => Conversation.fromJson(
    (await _request('POST', '/buy-requests/$id/conversation'))['conversation']
        as Map<String, dynamic>,
  );
  @override
  Future<List<Conversation>> fetchResponses(String id) async =>
      ((await _request(
                'GET',
                '/buy-requests/$id/conversations',
              ))['conversations']
              as List)
          .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
          .toList();

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? search,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Please sign in again.');
    final uri = Uri.parse('${ApiConfig.apiBaseUrl}$path').replace(
      queryParameters: search == null || search.trim().isEmpty
          ? null
          : {'search': search.trim()},
    );
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception(
        'The request timed out. Refresh to check whether it was saved before trying again.',
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }
    if (response.statusCode == 401) {
      await AuthService.expireSession();
      throw Exception('Please sign in again.');
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'The server sent an unexpected response. Please try again.',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw Exception(
      data['message'] as String? ?? 'Could not load buy requests.',
    );
  }
}
