import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'session_state.dart';

/// OneSignal push: the nudge that gets someone to open the app.
///
/// The inbox row is the source of truth and the push is only a nudge, so this
/// class is deliberately incapable of breaking anything. Every entry point
/// checks [isConfigured] and [isReady] first, and every OneSignal call is
/// wrapped: a missing App ID, a revoked key or an uninitialised native SDK
/// degrades to "no push", never to a crash or a failed login.
///
/// The whole SDK is confined to this file on purpose. Screens and services talk
/// to [PushService], so push can be switched off — or removed later — without
/// touching a single call site.
class PushService {
  /// The OneSignal App ID from the dashboard (Settings -> Keys & IDs).
  ///
  /// This is the *public* half of the OneSignal credentials: it ships inside
  /// the APK and anyone can read it out of the binary, which is why it belongs
  /// here in plain sight rather than being smuggled in through --dart-define.
  /// The REST API key (the `os_v2_app_...` string) is the secret half and must
  /// never be pasted into this file — it lives only in the Laravel .env, where
  /// the server signs its push requests.
  static const String appId = 'f2d66263-e9e1-46a8-bb24-c0c017a89afd';

  static bool get isConfigured => appId.trim().isNotEmpty;

  /// True once the SDK is actually up. Callers gate on this so an
  /// unconfigured build never reaches a method channel.
  static bool get isReady => _ready;

  static bool _ready = false;
  static bool _permissionRequested = false;
  static void Function()? _onOpened;

  /// Starts the SDK. Safe to call before `runApp`, and safe to call twice.
  ///
  /// [onNotificationOpened] fires when a push is tapped, including the cold-start
  /// case where the app was launched by the tap itself — that is how the user
  /// lands on the inbox rather than staring at the home feed wondering what the
  /// notification was about.
  static Future<void> initialize({
    void Function()? onNotificationOpened,
  }) async {
    if (!isConfigured) {
      debugPrint('[push] no OneSignal App ID configured; push disabled.');
      return;
    }
    if (_ready) return;

    _onOpened = onNotificationOpened;
    try {
      await OneSignal.initialize(appId);

      // Foreground notifications are shown, not swallowed. Someone approving a
      // seller's application is often looking at the app at that moment, and
      // without this the banner is silently dropped while the app is open.
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        OneSignal.Notifications.displayNotification(
          event.notification.notificationId,
        );
      });

      OneSignal.Notifications.addClickListener((_) => _onOpened?.call());

      _ready = true;
      _followSession();
    } catch (error) {
      // A push SDK that will not start is a missing feature, not a failed app.
      debugPrint(
        '[push] OneSignal init failed, continuing without push: $error',
      );
    }
  }

  /// Registers this device under the signed-in user's USR_ID.
  ///
  /// The backend targets `include_aliases: {external_id: [USR_ID]}`, so this is
  /// what makes a notification reach this person at all. Without it OneSignal
  /// matches zero devices and answers 200 with a per-recipient error.
  static Future<void> login(String externalId) async {
    if (!_ready) return;
    try {
      await OneSignal.login(externalId);
    } catch (error) {
      debugPrint('[push] login failed: $error');
    }
  }

  /// Detaches the device from whoever was signed in before.
  ///
  /// Without this the next person to sign in on a shared phone keeps receiving
  /// the previous user's notifications.
  static Future<void> logout() async {
    if (!_ready) return;
    try {
      await OneSignal.logout();
    } catch (error) {
      debugPrint('[push] logout failed: $error');
    }
  }

  /// Asks for the Android 13+ POST_NOTIFICATIONS permission, once per launch.
  ///
  /// Called when the inbox is first opened rather than at launch: a permission
  /// prompt in the first two seconds of an app, before the user has seen what
  /// the feature is for, is the fastest way to a permanent denial.
  static Future<void> requestPermissionIfNeeded() async {
    if (!_ready || _permissionRequested) return;
    _permissionRequested = true;
    try {
      await OneSignal.Notifications.requestPermission(false);
    } catch (error) {
      debugPrint('[push] permission request failed: $error');
    }
  }

  /// The external_id for a cached user record, or null when signed out.
  ///
  /// Pure and static so the mapping can be tested without a device: the id is
  /// the app's own USR_ID, which is exactly what the backend sends as
  /// `include_aliases.external_id`.
  static String? externalIdFor(Map<String, dynamic>? user) {
    final id = (user?['USR_ID'] as Object?)?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Keeps the push identity in step with the session.
  ///
  /// [SessionState] is already the single source of truth for who is signed in,
  /// and it changes on login, registration, a background refresh and sign-out.
  /// Listening to it puts the login/logout pair in one place instead of four
  /// auth paths — and, more importantly, makes it impossible for a new sign-in
  /// to inherit the previous user's notification identity.
  static void _followSession() {
    SessionState.instance.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  static void _onSessionChanged() {
    // Before the disk cache is seeded `user` is null, and reacting to that
    // would detach a device that is about to be re-attached moments later.
    // init() notifies once the cache is in, so the signed-in case still lands.
    if (!SessionState.instance.isInitialised) return;

    final id = externalIdFor(SessionState.instance.user);
    if (id == null) {
      unawaited(logout());
    } else {
      unawaited(login(id));
    }
  }
}
