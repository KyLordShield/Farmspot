import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Chrome + Laravel on the same machine -> localhost works fine.
  // When we move to the physical phone, this becomes your PC's LAN IP.
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  /// Attempts login. Returns null on success, or an error message string on failure.
  static Future<String?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Accept': 'application/json'},
        body: {
          'email': email,
          'password': password,
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final token = data['token'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        return null; // null = success
      }

      // Backend sends a 'message' field for both 401 and 403 cases.
      return data['message'] ?? 'Login failed. Please try again.';
    } catch (e) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  /// Attempts registration. Returns null on success, or an error message string
  /// on failure. Also stores the token so the user is logged in immediately.
  static Future<String?> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String mobileNumber,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Accept': 'application/json'},
        body: {
          'USR_NAME': name,
          'USR_EMAIL': email,
          'USR_PASSWORD': password,
          'USR_PASSWORD_confirmation': passwordConfirmation,
          'USR_MOBILE_NUMBER': mobileNumber,
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final token = data['token'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        return null; // null = success
      }

      // 422 validation failure: { message, errors: { field: [messages] } }.
      // Return the first field error we find, e.g. duplicate email/mobile.
      final errors = data['errors'];
      if (errors is Map) {
        for (final fieldErrors in errors.values) {
          if (fieldErrors is List && fieldErrors.isNotEmpty) {
            return fieldErrors.first.toString();
          }
        }
      }

      return data['message'] ?? 'Sign up failed. Please try again.';
    } catch (e) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> logout() async {
    final token = await getToken();

    if (token != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {
        // Ignore network errors here — we still want to clear the local
        // token and log the user out on-device even if the request fails.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }
}