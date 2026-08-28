import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
  // TODO: replace with real auth check once backend is available.
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const HomeScreen()),
  );
}

  void _goToSignUp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const FarmSpotHeader(),
            const SizedBox(height: 8),
            const FarmSpotLogo(size: 190),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  FarmSpotTextField(
                    hint: 'user name',
                    controller: _usernameController,
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'password',
                    controller: _passwordController,
                    obscureText: true,
                  ),
                  const SizedBox(height: 26),
                  FarmSpotButton(
                    label: 'Log In',
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 20),
                  FarmSpotSwitchLink(
                    question: "----- Don't have an Account?-----",
                    actionLabel: 'Create Account',
                    onTap: _goToSignUp,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
