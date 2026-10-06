import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_chat_service.dart';
import 'session_state.dart';

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

/// Outcome of asking for a reset code.
///
/// [debugCode] is only ever non-null when the backend runs with
/// APP_ENV=local and PASSWORD_RESET_EXPOSE_CODE=true. It exists so the flow can
/// be tested before Gmail SMTP is configured; the forgot-password screen shows it
/// in an obvious "local only" banner rather than pretending it was emailed.
class PasswordResetRequestResult {
  final bool success;
  final int? statusCode;
  final String? message;
  final bool isNetworkError;
  final String? debugCode;

  const PasswordResetRequestResult({
    required this.success,
    this.statusCode,
    this.message,
    this.isNetworkError = false,
    this.debugCode,
  });
}

class AuthService {
  // Chrome + Laravel on the same machine -> localhost works fine.
  // When we move to the physical phone, this becomes your PC's LAN IP.
  static const String baseUrl = 'http://10.143.212.234:8000/api';

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
        await _cacheUser(data['user'] as Map<String, dynamic>);

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

  /// Single funnel for every `user_data` write.
  ///
  /// Writing the cache and telling [SessionState] must never be two separate
  /// steps: a write that skipped the notifier left the bottom nav showing a
  /// stale role until something happened to refetch. Keeping it in one helper
  /// means the disk and the in-memory session cannot drift apart.
  static Future<void> _cacheUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SessionState.userPrefsKey, jsonEncode(user));
    SessionState.instance.applyUser(user);
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
        await _cacheUser(data['user'] as Map<String, dynamic>);

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
        await _cacheUser(data['user'] as Map<String, dynamic>);

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
        await _cacheUser(data['user'] as Map<String, dynamic>);

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
          await _cacheUser(user);
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
          await _cacheUser(user);
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
    final userJson = prefs.getString(SessionState.userPrefsKey);
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

      await _cacheUser(data);
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Reports whether seller mode is active (USR_IS_SELLER == 1), fetching the
  /// latest user from the server (GET /api/user) and falling back to the cached
  /// copy if the request fails.
  ///
  /// Prefer [SessionState.instance.isSeller] when deciding what to render: it
  /// is synchronous and already correct on the first frame, whereas this call
  /// blocks on HTTP and cannot be used during build. Keep this for the cases
  /// that genuinely need a round trip, such as pulling data that is gated
  /// behind the role.
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
        // Pull the authoritative user back so USR_IS_SELLER lands in the cache
        // and in [SessionState]. Without this the nav kept rendering the old
        // role: activateSeller used to leave `user_data` untouched, so Map and
        // Insights — which read the cache — hid "My Farm" even after the user
        // had successfully become a seller.
        await fetchUser();
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
      if (response.statusCode == 200) {
        // Same reasoning as activateSeller: the cached role has to follow the
        // toggle or the nav keeps offering My Farm to a deactivated seller.
        await fetchUser();
        return null;
      }
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
    await prefs.remove(SessionState.userPrefsKey);
    SessionState.instance.clear();
    // The AI transcript is a process-wide singleton so it can outlive the chat
    // screen. Without this, whoever signs in next would be continuing the
    // previous user's conversation.
    AiChatSession.instance.clear();
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

  // --- Forgot password (emailed 6-digit code) -------------------------------
  //
  // Sibling of attemptLogin rather than a new service: it hits the same API
  // base URL, uses the same exception -> isNetworkError mapping, and has the
  // same "never throw at the widget" contract the login screen relies on.
  //
  // Note there is no admin equivalent. Admin reset was withdrawn by owner
  // decision (docs/admin_audit_report.md, S1); these routes only ever serve
  // GENERAL_USER accounts.

  /// Asks the API to email a 6-digit code to [email].
  ///
  /// Deliberately reports the same success for known and unknown addresses so
  /// the screen cannot be used to discover which emails have accounts - the
  /// backend does the same. [PasswordResetRequestResult] carries [debugCode]
  /// which the backend only fills when APP_ENV=local and
  /// PASSWORD_RESET_EXPOSE_CODE=true, i.e. while SMTP is still being set up.
  static Future<PasswordResetRequestResult> requestPasswordResetCode(
    String email,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/forgot-password'),
            headers: {'Accept': 'application/json'},
            body: {'email': email},
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return PasswordResetRequestResult(
          success: true,
          message: data['message'] as String?,
          debugCode: data['debug_code'] as String?,
        );
      }

      return PasswordResetRequestResult(
        success: false,
        statusCode: response.statusCode,
        message: data['message'] as String?,
      );
    } on TimeoutException {
      debugPrint('AuthService.requestPasswordResetCode: request timed out.');
      return const PasswordResetRequestResult(success: false, isNetworkError: true);
    } on SocketException {
      debugPrint('AuthService.requestPasswordResetCode: socket error (no connection).');
      return const PasswordResetRequestResult(success: false, isNetworkError: true);
    } on http.ClientException {
      debugPrint('AuthService.requestPasswordResetCode: client error (no connection).');
      return const PasswordResetRequestResult(success: false, isNetworkError: true);
    } catch (e) {
      debugPrint('AuthService.requestPasswordResetCode: unexpected error: $e');
      return PasswordResetRequestResult(success: false);
    }
  }

  /// Completes the reset with the emailed [code] and the new [password].
  ///
  /// The code is normalised here (spaces and dashes stripped, lowercased) so the
  /// user can paste `123 456` straight out of the email. A successful reset
  /// revokes every Sanctum token server-side, so any device already signed in is
  /// signed out and must use the new password.
  ///
  /// 422 carries a human message on purpose: the backend distinguishes expired /
  /// already-used / too-many-attempts so the user knows whether to request a
  /// fresh code instead of guessing again.
  static Future<AuthLoginResult> resetPasswordWithCode({
    required String email,
    required String code,
    required String password,
  }) async {
    final normalizedCode = code.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/reset-password'),
            headers: {'Accept': 'application/json'},
            body: {
              'email': email,
              'code': normalizedCode,
              'password': password,
              'password_confirmation': password,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // No token to cache: the reset deliberately logs every device out, so
        // the user goes back to the login screen and signs in with the new
        // password. Leaving any stale auth_token here would be misleading.
        return const AuthLoginResult(success: true);
      }

      return AuthLoginResult(
        success: false,
        statusCode: response.statusCode,
        message: data['message'] as String?,
      );
    } on TimeoutException {
      debugPrint('AuthService.resetPasswordWithCode: request timed out.');
      return const AuthLoginResult(success: false, isNetworkError: true);
    } on SocketException {
      debugPrint('AuthService.resetPasswordWithCode: socket error (no connection).');
      return const AuthLoginResult(success: false, isNetworkError: true);
    } on http.ClientException {
      debugPrint('AuthService.resetPasswordWithCode: client error (no connection).');
      return const AuthLoginResult(success: false, isNetworkError: true);
    } catch (e) {
      debugPrint('AuthService.resetPasswordWithCode: unexpected error: $e');
      return AuthLoginResult(success: false);
    }
  }
}