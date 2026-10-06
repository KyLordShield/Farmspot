import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/farmspot_loader.dart';
import '../services/auth_service.dart';
import 'reset_password_screen.dart';

/// Step 1 of "forgot password": collect the email and have the API email a
/// 6-digit code.
///
/// Deliberately worded so it never confirms whether an address is registered,
/// because the backend returns the same answer either way. Telling the user
/// "we sent you a code" only when the account exists would turn this screen
/// into a way to enumerate FarmSpot users.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  bool _isLoading = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Mirrors the server rule (`required`, `email`, `max:200`) so the common
  /// mistakes are caught on-device instead of as a 422 round trip.
  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Please enter your email.';
    if (email.length > 200) return 'That email address is too long.';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!valid) return 'Please enter a valid email address.';
    return null;
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();

    final emailError = _validateEmail(_emailController.text);
    if (emailError != null) {
      setState(() => _emailError = emailError);
      return;
    }

    final email = _emailController.text.trim();

    setState(() => _isLoading = true);
    showFarmSpotLoading(context, message: 'Sending code...');

    final result = await AuthService.requestPasswordResetCode(email);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _isLoading = false);

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

    if (result.success) {
      // Straight to step 2. No "code sent" confirmation dialog in between: the
      // generic wording means we genuinely do not know if an email went out,
      // and a dialog claiming it did would be a lie for unknown addresses.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            email: email,
            debugCode: result.debugCode,
          ),
        ),
      );
      return;
    }

    if (result.statusCode == 422) {
      setState(() => _emailError = 'Please enter a valid email address.');
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        title: 'Check Your Email',
        message: 'Please enter a valid email address and try again.',
      );
      return;
    }

    if (result.statusCode == 429) {
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        icon: Icons.timer_outlined,
        title: 'Too Many Requests',
        message: 'You have requested several codes just now. Please wait a '
            'minute before asking for another one.',
      );
      return;
    }

    showFarmAlert(
      context,
      type: FarmAlertType.error,
      title: 'Something Went Wrong',
      message: 'We could not send a reset code right now. Please try again in '
          'a moment.',
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
                  const Text(
                    'Forgot Your Password?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the email you use for FarmSpot and we will send you '
                    'a 6-digit code to set a new password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 26),
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
                  const SizedBox(height: 26),
                  FarmSpotButton(
                    label: _isLoading ? 'Sending...' : 'Send Reset Code',
                    onPressed: _isLoading ? () {} : () => _handleSubmit(),
                  ),
                  const SizedBox(height: 20),
                  FarmSpotSwitchLink(
                    question: '----- Remembered your password? -----',
                    actionLabel: 'Back to Log In',
                    onTap: () => Navigator.of(context).pop(),
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