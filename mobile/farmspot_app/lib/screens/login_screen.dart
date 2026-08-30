import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await AuthService.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _errorMessage = error;
    });

    if (error == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
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
                    hint: 'email',
                    controller: _emailController,
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'password',
                    controller: _passwordController,
                    obscureText: true,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 26),
                  FarmSpotButton(
                    label: _isLoading ? 'Logging in...' : 'Log In',
                    onPressed: _isLoading ? () {} : () => _handleLogin(),
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