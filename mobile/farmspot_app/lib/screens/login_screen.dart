import '../legal/legal.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/lottie_loader.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'account_appeal_screen.dart';
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
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Please enter your email.';
    final valid =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!valid) return 'Please enter a valid email address.';
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) return 'Please enter your password.';
    return null;
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();

    final emailError = _validateEmail(_emailController.text);
    final passwordError = _validatePassword(_passwordController.text);
    if (emailError != null || passwordError != null) {
      setState(() {
        _emailError = emailError;
        _passwordError = passwordError;
      });
      return;
    }

    setState(() => _isLoading = true);
    showFarmLottieLoading(context, message: 'Signing in...');

    final result = await AuthService.attemptLogin(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _isLoading = false);

    if (result.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
    _showLoginError(result);
  }

  void _showLoginError(AuthLoginResult result) {
    if (result.isNetworkError) {
      showFarmAlert(
        context,
        type: FarmAlertType.error,
        icon: Icons.wifi_off_rounded,
        title: 'No Connection',
        message: "We couldn't reach FarmSpot. Please check your internet "
            'connection and try again.',
        buttonLabel: 'Try Again',
      );
      return;
    }

    if (result.statusCode == 401) {
      showFarmAlert(
        context,
        type: FarmAlertType.error,
        title: "Can't Sign In",
        message: 'The email or password is incorrect. Please check your '
            'details and try again.',
      );
      return;
    }

    if (result.statusCode == 403) {
      // Taken down by an admin: unlike a plain deactivation this is appealable,
      // so send them to the re-evaluation form instead of a dead-end alert. The
      // email they typed is carried over; the password is re-entered there.
      if (result.isTakenDown) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountAppealScreen(
              email: _emailController.text.trim(),
              takedownReason: result.reason,
            ),
          ),
        );
        return;
      }

      if (result.isPlainlyDeactivated) {
        showFarmAlert(
          context,
          type: FarmAlertType.warning,
          title: 'Account Deactivated',
          message: 'Your account has been deactivated. Please contact your '
              'farm association for help.',
        );
        return;
      }

      final serverMessage = result.message ?? '';
      if (serverMessage.contains('pending')) {
        showFarmAlert(
          context,
          type: FarmAlertType.info,
          title: 'Account Not Verified Yet',
          message: 'Your account is still waiting to be verified. '
              'Please try again later.',
        );
      } else {
        showFarmAlert(
          context,
          type: FarmAlertType.warning,
          title: 'FarmSpot Buyers & Farmers Only',
          message: 'This app is for buyers and farmers. Admin accounts can '
              'only log in on the website.',
        );
      }
      return;
    }

    if (result.statusCode == 422) {
      // Server-side format gate — rare since we pre-validate on-device.
      final serverMessage = result.message ?? '';
      if (serverMessage.toLowerCase().contains('email')) {
        setState(() => _emailError = 'Please enter a valid email address.');
      }
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        title: 'Check Your Details',
        message: 'Please correct the highlighted fields and try again.',
      );
      return;
    }

    showFarmAlert(
      context,
      type: FarmAlertType.error,
      title: 'Something Went Wrong',
      message: 'Something went wrong on our side. Please try again in a moment.',
    );
  }

  void _goToSignUp() {
    Navigator.of(context).pushReplacement(
      farmFadeRoute(const SignUpScreen()),
    );
  }

  /// Pushes, not replaces: the email the user just typed stays on the login
  /// screen underneath, so if they remember the password they are one tap away
  /// back instead of retyping it.
  void _goToForgotPassword() {
    Navigator.of(context).push(
      farmFadeRoute(const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FarmSpotLogo(size: 190),
                    const SizedBox(height: 28),
                    FarmSpotTextField(
                      hint: 'email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _emailError,
                      onChanged: (_) {
                        if (_emailError != null) {
                          setState(() => _emailError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    FarmSpotTextField(
                      hint: 'password',
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      errorText: _passwordError,
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                      },
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.black45,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _goToForgotPassword,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FarmSpotButton(
                      label: _isLoading ? 'Logging in...' : 'Log In',
                      onPressed: _isLoading ? () {} : () => _handleLogin(),
                    ),
                    const SizedBox(height: 18),
                    FarmSpotSwitchLink(
                      question: "----- Don't have an Account?-----",
                      actionLabel: 'Create Account',
                      onTap: _goToSignUp,
                    ),
                    const LegalLinks(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}