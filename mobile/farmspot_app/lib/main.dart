import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const FarmSpotApp());
}

class FarmSpotApp extends StatelessWidget {
  const FarmSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FarmSpot',
      debugShowCheckedModeBanner: false,
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
  Future<void> _bootstrap() async {
    final results = await Future.wait<String?>([
      AuthService.getToken(),
      Future<String?>.delayed(const Duration(milliseconds: 1950), () => null),
    ]);
    if (!mounted) return;
    setState(() {
      _ready = true;
      _token = results.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashScreen();
    return _token != null ? const HomeScreen() : const WelcomeScreen();
  }
}