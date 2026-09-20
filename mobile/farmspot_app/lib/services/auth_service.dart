import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Structured login outcome so screens can distinguish network failures from
/// auth failures (401/403) and show the right friendly message.
class AuthLoginResult {
  final bool success;
  final int? statusCode;
  final String? message;
  final bool isNetworkError;

  const AuthLoginResult({
    required this.success,
    this.statusCode,
    this.message,
    this.isNetworkError = false,
  });
}

/// Structured registration outcome: same shape as [AuthLoginResult], plus the
/// Laravel 422 `errors` map (backend field name -> message list) so the sign-up
/// screen can show friendly text inline under the right field instead of
/// printing raw "The USR_EMAIL ..." messages.
class AuthRegisterResult {
  final bool success;
  final int? statusCode;
  final String? message;
  final bool isNetworkError;
  final Map<String, List<String>> fieldErrors;

  const AuthRegisterResult({
    required this.success,
    this.statusCode,
    this.message,
    this.isNetworkError = false,
    this.fieldErrors = const {},
  });
}

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
        await prefs.setString('user_data', jsonEncode(data['user']));

        // Make GET /api/user the single source of truth for the cached user
        // BEFORE login returns (and before the first post-login screen builds).
        // This guarantees `user_data` holds authoritative USR_IS_SELLER state
        // (e.g. approved seller = 1), so the very first screen's isSeller()
        // check can never fall back to an empty/stale cache and hide My Farm.
        // Safe to ignore failure here; the login-response payload stays cached.
        await fetchUser();

        return null; // null = success
      }

      // Backend sends a 'message' field for both 401 and 403 cases.
      return data['message'] ?? 'Login failed. Please try again.';
    } catch (e) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  /// Login variant that keeps the raw server response so the UI can map 401 vs
  /// 403 vs network failure to friendly messages. Sends the exact same payload
  /// as [login]. On success it stores the token and refreshes the cached user
  /// exactly like [login] does.
  static Future<AuthLoginResult> attemptLogin(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: {'Accept': 'application/json'},
            body: {
              'email': email,
              'password': password,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final token = data['token'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('user_data', jsonEncode(data['user']));

        // Same authoritative user refresh as login() — see its comment.
        await fetchUser();

        return const AuthLoginResult(success: true);
      }

      return AuthLoginResult(
        success: false,
        statusCode: response.statusCode,
        message: data['message'] as String?,
      );
    } on TimeoutException {
      debugPrint('AuthService.attemptLogin: request timed out.');
      return const AuthLoginResult(
        success: false,
        isNetworkError: true,
      );
    } on SocketException {
      debugPrint('AuthService.attemptLogin: socket error (no connection).');
      return const AuthLoginResult(
        success: false,
        isNetworkError: true,
      );
    } on http.ClientException {
      debugPrint('AuthService.attemptLogin: client error (no connection).');
      return const AuthLoginResult(
        success: false,
        isNetworkError: true,
      );
    } catch (e) {
      debugPrint('AuthService.attemptLogin: unexpected error: $e');
      return AuthLoginResult(success: false);
    }
  }

  /// Registration variant that keeps the backend `errors` map (see
  /// [AuthRegisterResult]) so the screen can map 422 validation failures to
  /// friendly inline messages. Sends the exact same payload as [register] and
  /// stores the token + refreshed cached user on success exactly like it does.
  static Future<AuthRegisterResult> attemptRegister({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String mobileNumber,
    String? address,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/register'),
            headers: {'Accept': 'application/json'},
            body: {
              'USR_NAME': name,
              'USR_EMAIL': email,
              'USR_PASSWORD': password,
              'USR_PASSWORD_confirmation': passwordConfirmation,
              'USR_MOBILE_NUMBER': mobileNumber,
              if (address != null) 'address': address.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final token = data['token'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('user_data', jsonEncode(data['user']));

        await fetchUser();

        return const AuthRegisterResult(success: true);
      }

      var fieldErrors = const <String, List<String>>{};
      if (data is Map && data['errors'] is Map) {
        fieldErrors = <String, List<String>>{
          for (final entry in (data['errors'] as Map).entries)
            entry.key.toString(): entry.value is List
                ? entry.value.map((e) => e.toString()).toList()
                : [entry.value.toString()],
        };
      }

      return AuthRegisterResult(
        success: false,
        statusCode: response.statusCode,
        message: data['message'] as String?,
        fieldErrors: fieldErrors,
      );
    } on TimeoutException {
      debugPrint('AuthService.attemptRegister: request timed out.');
      return const AuthRegisterResult(success: false, isNetworkError: true);
    } on SocketException {
      debugPrint('AuthService.attemptRegister: socket error (no connection).');
      return const AuthRegisterResult(success: false, isNetworkError: true);
    } on http.ClientException {
      debugPrint('AuthService.attemptRegister: client error (no connection).');
      return const AuthRegisterResult(success: false, isNetworkError: true);
    } catch (e) {
      debugPrint('AuthService.attemptRegister: unexpected error: $e');
      return AuthRegisterResult(success: false);
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
    String? address,
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
          // Optional on signup: only sent when the buyer typed one.
          if (address != null) 'address': address.trim(),
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final token = data['token'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('user_data', jsonEncode(data['user']));

        // Same as login: fetch the authoritative user via GET /api/user so the
        // cached copy is fresh before the app proceeds to the first screen.
        await fetchUser();

        return null; // null = success
      }

      // 422 validation failure: { message, errors: { field: [messages] } }.
      // Return the first field error we find, e.g. duplicate email/mobile.
      return _firstFieldError(data) ??
          (data['message'] as String? ?? 'Sign up failed. Please try again.');
    } catch (e) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  /// Edits the buyer's own profile (PATCH /api/user). Only the fields that are
  /// explicitly provided (non-null) are sent — an absent one is left untouched
  /// on the server, so callers can send exactly what changed. Matching this
  /// file's conventions it never throws; `error` is null on success and the
  /// fresh user object is returned (and re-cached so next launch is current).
  static Future<({String? error, Map<String, dynamic>? user})> updateProfile({
    String? name,
    String? mobileNumber,
    String? address,
  }) async {
    final token = await getToken();
    if (token == null) {
      return (error: 'Not logged in.', user: null);
    }

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {
          // An empty string is still sent so a caller can deliberately clear
          // the field back to blank; absent fields are simply not sent.
          if (name != null) 'name': name.trim(),
          if (mobileNumber != null) 'mobile_number': mobileNumber.trim(),
          if (address != null) 'address': address.trim(),
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = data['user'];
        if (user is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', jsonEncode(user));
          return (error: null, user: user);
        }
        return (error: null, user: null);
      }

      return (
        error: _firstFieldError(data) ??
            (data['message'] as String? ?? 'Could not update profile.'),
        user: null,
      );
    } catch (e) {
      return (
        error: 'Could not reach the server. Check your connection.',
        user: null,
      );
    }
  }

  /// Replaces the buyer's profile photo (POST /api/user/photo). Uses the same
  /// bytes-based multipart pattern as the farm/listing photo uploads — the
  /// backend's `photo` field expects a real file part, not JSON. Returns the
  /// fresh user object (and re-caches it) on success, or an error message.
  static Future<({String? error, Map<String, dynamic>? user})>
      uploadProfilePhoto(XFile photo) async {
    final token = await getToken();
    if (token == null) {
      return (error: 'Not logged in.', user: null);
    }

    dynamic data;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/user/photo'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      final bytes = await photo.readAsBytes();
      final uploadName = _uploadFileName(photo.name, photo.path);
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: uploadName,
          contentType: _contentTypeFor(uploadName),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = data['user'];
        if (user is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', jsonEncode(user));
          return (error: null, user: user);
        }
        return (error: null, user: null);
      }
    } catch (e) {
      // Falls through to the generic network error below.
    }

    return (
      error: _firstFieldError(data) ??
          (data is Map && data['message'] is String
              ? data['message'] as String
              : 'Could not reach the server. Check your connection.'),
      user: null,
    );
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_data');
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  /// Fetches the latest user record (GET /api/user) and refreshes the cached
  /// copy so seller status reflects current server state, not just login-time.
  /// Returns null (leaving the cache untouched) if not logged in or the
  /// request fails.
  static Future<Map<String, dynamic>?> fetchUser() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(data));
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Reports whether seller mode is active (USR_IS_SELLER == 1), fetching the
  /// latest user from the server (GET /api/user) and falling back to the cached
  /// copy if the request fails. Shared so the first post-login screen can decide
  /// which bottom nav (seller vs buyer) to show without waiting for Profile.
  static Future<bool> isSeller() async {
    var user = await fetchUser();
    user ??= await getUser();
    if (user == null) return false;
    final v = user['USR_IS_SELLER'];
    final isSeller = v is int ? v == 1 : int.tryParse(v?.toString() ?? '') == 1;
    return isSeller;
  }

  /// Activates seller mode for the authenticated user (POST /seller/activate).
  /// Returns an error message (null on success) plus whether the server
  /// reactivated an already-approved seller ({reactivated: true}) or routed the
  /// user into the first-time wizard flow ({reactivated: false}).
  static Future<({String? error, bool reactivated})> activateSeller() async {
    final token = await getToken();
    if (token == null) {
      return (error: 'Not logged in.', reactivated: false);
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/seller/activate'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return (
          error: null,
          reactivated: data['reactivated'] == true,
        );
      }
      return (
        error: data['message'] as String? ?? 'Could not activate seller mode.',
        reactivated: false,
      );
    } catch (_) {
      return (
        error: 'Could not reach the server. Check your connection.',
        reactivated: false,
      );
    }
  }

  /// Deactivates seller mode for the authenticated user (POST /seller/deactivate).
  /// Returns null on success, or an error message on failure.
  static Future<String?> deactivateSeller() async {
    final token = await getToken();
    if (token == null) return 'Not logged in.';

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/seller/deactivate'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return null;
      return data['message'] ?? 'Could not deactivate seller mode.';
    } catch (_) {
      return 'Could not reach the server. Check your connection.';
    }
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
    await prefs.remove('user_data');
  }

  /// Extracts the first field error from a Laravel 422 body
  /// ( { errors: { field: [messages] } } ), or null when not present.
  static String? _firstFieldError(dynamic data) {
    if (data is Map && data['errors'] is Map) {
      for (final fieldErrors in data['errors'].values) {
        if (fieldErrors is List && fieldErrors.isNotEmpty) {
          return fieldErrors.first.toString();
        }
      }
    }
    return null;
  }

  /// Same fallback used by the farm uploads: some pickers yield an empty name
  /// and an empty path, so without a real filename Laravel would not treat the
  /// part as a file upload at all.
  static String _uploadFileName(String name, String path) {
    if (name.isNotEmpty) return name;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isNotEmpty) {
      final fromPath = normalized.substring(normalized.lastIndexOf('/') + 1);
      if (fromPath.isNotEmpty) return fromPath;
    }
    return 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  static http.MediaType _contentTypeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return http.MediaType('image', 'jpeg');
      case 'png':
        return http.MediaType('image', 'png');
      case 'webp':
        return http.MediaType('image', 'webp');
      case 'gif':
        return http.MediaType('image', 'gif');
      case 'heic':
        return http.MediaType('image', 'heic');
      default:
        return http.MediaType('image', 'jpeg');
    }
  }
}