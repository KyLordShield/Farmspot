/// Single place that decides which backend the app talks to.
///
/// Everything network-facing reads from here, so pointing the app at a server
/// is a build-time choice — never an edit in each service file.
///
/// - Local USB / Chrome development uses the defaults (`127.0.0.1`), which
///   work with `adb reverse tcp:8000 tcp:8000`.
/// - A deployment or real-server build overrides it without touching code:
///
///       flutter run      --dart-define=API_BASE_URL=https://api.example.com/api
///       flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api
///
/// The image-detect microservice lives on a separate port of the same host,
/// so it gets its own knob.
class ApiConfig {
  const ApiConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  static const String imageDetectBaseUrl = String.fromEnvironment(
    'IMAGE_DETECT_BASE_URL',
    defaultValue: 'http://127.0.0.1:8001',
  );
}