import 'dart:async';

import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
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
  // Started here but deliberately not awaited: a push SDK that is slow, absent
  // or unconfigured must not delay the splash. Everything downstream is a no-op
  // until it reports ready, and the inbox does not depend on it.
  unawaited(PushService.initialize(onNotificationOpened: _openNotifications));
  runApp(const FarmSpotApp());
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

class FarmSpotApp extends StatelessWidget {
  const FarmSpotApp({super.key});

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
  String? _token;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Read the saved token while the splash plays; never swap the screen
  /// before the splash has had its moment.
  ///
  /// [SessionState.init] rides along in the same window. Seeding the role here
  /// — behind the splash rather than in the first screen's `initState` — is
  /// what stops the bottom nav from painting a buyer nav and then swapping to
  /// the seller nav once the role resolves. It costs no extra wall-clock time
  /// because the 1950ms splash delay is already the long pole.
  Future<void> _bootstrap() async {
    final results = await Future.wait<Object?>([
      AuthService.getToken(),
      SessionState.instance.init(),
      Future<Object?>.delayed(const Duration(milliseconds: 1950), () => null),
    ]);
    if (!mounted) return;
    setState(() {
      _ready = true;
      _token = results.first as String?;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashScreen();
    return _token != null ? const HomeScreen() : const WelcomeScreen();
  }
}
