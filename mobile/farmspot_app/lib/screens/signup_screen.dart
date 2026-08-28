import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _usernameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleCreateAccount() {
    // TODO: hook up to backend once available.
    debugPrint('Create account tapped — no backend wired yet.');
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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
                  Row(
                    children: [
                      Expanded(
                        child: FarmSpotTextField(
                          hint: 'Lastname',
                          controller: _lastNameController,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FarmSpotTextField(
                          hint: 'FirstName',
                          controller: _firstNameController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'user name',
                    controller: _usernameController,
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'mobile number',
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'address',
                    controller: _addressController,
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'password',
                    controller: _passwordController,
                    obscureText: true,
                  ),
                  const SizedBox(height: 26),
                  FarmSpotButton(
                    label: 'Create Account',
                    trailingIcon: Icons.arrow_forward,
                    onPressed: _handleCreateAccount,
                  ),
                  const SizedBox(height: 20),
                  FarmSpotSwitchLink(
                    question: '----- Already have an Account?-----',
                    actionLabel: 'Log In',
                    onTap: _goToLogin,
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
