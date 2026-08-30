import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateAccount() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await AuthService.register(
      name: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
          .trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _confirmPasswordController.text,
      mobileNumber: _mobileController.text.trim(),
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
                    hint: 'email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
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
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'confirm password',
                    controller: _confirmPasswordController,
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
                    label: _isLoading ? 'Creating Account...' : 'Create Account',
                    trailingIcon: Icons.arrow_forward,
                    onPressed: _isLoading ? () {} : () => _handleCreateAccount(),
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
