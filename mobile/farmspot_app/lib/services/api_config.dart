import 'package:flutter/foundation.dart' show kReleaseMode;

/// Single place that decides which backend the app talks to.
///
/// Everything network-facing reads from here, so pointing the app at a server
/// is a runtime choice — no edits across the service files.
///
/// The rule is automatic:
/// - Debug/profile builds (`flutter run` on USB, with `adb reverse`) use the
///   localhost endpoints, exactly as before.
/// - Release builds (the installed APK) use the cloud endpoints on Render.
/// - A build-time `--dart-define` always wins over the rule, so you can still
///   force any server without touching code:
///
///       flutter run      --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
///       flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api
///
/// The image-detect microservice lives on a separate URL (its own Render
/// service), so it gets its own knob.
class ApiConfig {
  ApiConfig._();

  /// Local backend used while developing over USB (`adb reverse`).
  static const String _localApiBaseUrl = 'http://127.0.0.1:8000/api';
  static const String _localImageDetectBaseUrl = 'http://127.0.0.1:8001';

  /// Cloud backend on Render, used by release APKs.
  static const String _cloudApiBaseUrl = 'https://farmspot-api.onrender.com/api';
  static const String _cloudImageDetectBaseUrl = 'https://farmspot-detect.onrender.com';

  /// Build-time overrides; empty string means "not provided".
  static const String _overrideApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _overrideImageDetectBaseUrl =
      String.fromEnvironment('IMAGE_DETECT_BASE_URL');

  static String get apiBaseUrl => _overrideApiBaseUrl.isNotEmpty
      ? _overrideApiBaseUrl
      : (kReleaseMode ? _cloudApiBaseUrl : _localApiBaseUrl);

  static String get imageDetectBaseUrl => _overrideImageDetectBaseUrl.isNotEmpty
      ? _overrideImageDetectBaseUrl
      : (kReleaseMode ? _cloudImageDetectBaseUrl : _localImageDetectBaseUrl);
}