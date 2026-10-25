import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/premium_checkout.dart';
import 'api_config.dart';
import 'auth_service.dart';

abstract class PremiumCheckoutGateway {
  Future<PremiumCheckout> create();
  Future<PremiumCheckout> verify(String id);
}

class PremiumCheckoutService implements PremiumCheckoutGateway {
  final http.Client _client;
  PremiumCheckoutService({http.Client? client})
    : _client = client ?? http.Client();
  static final instance = PremiumCheckoutService();
  @override
  Future<PremiumCheckout> create() => _request('/premium/checkouts');
  @override
  Future<PremiumCheckout> verify(String id) =>
      _request('/premium/checkouts/${Uri.encodeComponent(id)}/verify');
  Future<PremiumCheckout> _request(String path) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Please sign in to continue.');
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${ApiConfig.apiBaseUrl}$path'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw Exception(
        'The request timed out. Retry to check your saved checkout.',
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }
    if (await AuthService.getToken() != token) {
      throw Exception('Your account changed. Please reopen checkout.');
    }
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message'] as String? ?? 'Could not check your test payment.',
      );
    }
    return PremiumCheckout.fromJson(data['checkout'] as Map<String, dynamic>);
  }
}
