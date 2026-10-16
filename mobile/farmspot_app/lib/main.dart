import 'dart:async';

import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/session_state.dart';

/// Navigator handle for pushes that arrive before the first frame.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap the decoded-image cache so a photo-heavy feed can't inflate the
  // process past the point where Android's low-memory killer reaps the app
  // (which dropped users back to the Home screen after using the camera).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  // A revoked token (admin deactivation, password reset) has to bounce the
  // user back to login even from a screen pushed deep on top of the gate, so
  // the reset runs on the root navigator rather than rebuilding one screen.
  SessionState.instance.onSessionExpired = _resetToLogin;
  // Started here but deliberately not awaited: a push SDK that is slow, absent
  // or unconfigured must not delay the splash. Everything downstream is a no-op
  // until it reports ready, and the inbox does not depend on it.
  unawaited(PushService.initialize(onNotificationOpened: _openNotifications));
  runApp(const FarmSpotApp());
}

/// Clears the whole navigation stack back to the login screen. Used when the
/// session turns out to be dead mid-use, so a user sitting on, say, a chat or a
/// listing screen cannot keep interacting with a token the server has revoked.
void _resetToLogin() {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

/// A tapped push opens the inbox, which is where the row it came from already
/// lives — the notification body only carries a title and a message, so
/// guessing a destination here would either dead-end or guess wrong.
void _openNotifications() {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  navigator.push(
    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
  );
}

class FarmSpotApp extends StatefulWidget {
  const FarmSpotApp({super.key});

  @override
  State<FarmSpotApp> createState() => _FarmSpotAppState();
}

class _FarmSpotAppState extends State<FarmSpotApp>
    with WidgetsBindingObserver {
  /// How often a foregrounded app re-checks that its token is still accepted.
  ///
  /// This deliberately lives above the [Navigator] rather than in [AuthGate].
  /// Every tab switches with `pushReplacement` on the root navigator, so the
  /// first tab tap replaces the route that holds AuthGate and disposes it — a
  /// watch owned there would be cancelled almost immediately, leaving a
  /// deactivated user able to browse every screen that does not happen to
  /// re-fetch the profile. Sited here, nothing the user navigates to can
  /// dispose it, which is what bounds how long a dead session stays usable.
  static const Duration _sessionCheckInterval = Duration(seconds: 30);
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSessionWatch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the moment a session revoked while the
    // app was backgrounded most needs re-checking.
    if (state == AppLifecycleState.resumed) {
      _checkSession();
    }
  }

  void _startSessionWatch() {
    _sessionTimer?.cancel();
    _sessionTimer =
        Timer.periodic(_sessionCheckInterval, (_) => _checkSession());
  }

  /// Re-validates the stored token. A rejection has already cleared the local
  /// session and reset the navigator to login via [SessionState], so there is
  /// nothing to reconcile here; a missing token just means nobody is signed in.
  Future<void> _checkSession() async {
    final token = await AuthService.getToken();
    if (token == null) return;
    await AuthService.validateSession();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FarmSpot',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: appTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;
  bool _splashDone = false;
  bool _bootstrapped = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Read the saved token while the splash plays; never swap the screen
  /// until the splash's logo fade-out has actually completed.
  ///
  /// [SessionState.init] rides along in the same window. Seeding the role here
  /// — behind the splash rather than in the first screen's `initState` — is
  /// what stops the bottom nav from painting a buyer nav and then swapping to
  /// the seller nav once the role resolves.
  Future<void> _bootstrap() async {
    String? token;
    try {
      final results = await Future.wait<Object?>([
        AuthService.getToken(),
        SessionState.instance.init(),
      ]);
      token = results.first as String?;
    } catch (_) {
      // A broken local session must not pin the app to the splash forever.
      token = null;
    }

    if (!mounted) return;
    _token = token;
    _bootstrapped = true;
    _maybeReady();

    // A stored token is trusted for the first frame, then checked straight
    // away rather than gating the splash on a network round trip. A revoked
    // token (admin deactivation, password reset) therefore ejects to login
    // within a moment of launch instead of opening onto a cached Home screen —
    // and a valid session never waits on the check to start.
    unawaited(_checkSession());

    // Safety net: if the splash animation somehow never fires its completion,
    // release the splash a few seconds in so the app is never stranded on a
    // permanent white screen. Normally `_splashDone` gets set first and this
    // becomes a no-op.
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted || _ready) return;
      _splashDone = true;
      _maybeReady();
    });
  }

  /// Re-validates the stored token. On rejection the session has already been
  /// cleared and the root navigator reset; this just reconciles the gate in the
  /// case it was not the visible route.
  Future<void> _checkSession() async {
    if (!mounted || _token == null) return;
    final stillValid = await AuthService.validateSession();
    if (!stillValid && mounted) {
      setState(() => _token = null);
    }
  }

  /// The splash fires this the moment its fade-out ends.
  void _onSplashFinished() {
    if (!mounted) return;
    _splashDone = true;
    _maybeReady();
  }

  void _maybeReady() {
    if (_ready || !_splashDone || !_bootstrapped) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Cross-fade between states so the splash's logo fade-out melts into the
    // first frame of the next screen instead of snapping.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: !_ready
          ? SplashScreen(
              key: const ValueKey('splash'), onFinished: _onSplashFinished)
          : _token != null
              ? const HomeScreen(key: ValueKey('home'))
              : const LoginScreen(key: ValueKey('login')),
    );
  }
}
