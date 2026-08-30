import 'package:flutter/material.dart';
import 'theme.dart';
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: AuthService.getToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final hasToken = snapshot.data != null;
        return hasToken ? const HomeScreen() : const WelcomeScreen();
      },
    );
  }
}