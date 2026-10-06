import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/farmspot_loader.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

/// Step 2 of "forgot password": trade the emailed 6-digit code for a new
/// password.
///
/// [debugCode] is non-null only when the backend runs with APP_ENV=local and
/// PASSWORD_RESET_EXPOSE_CODE=true. It is surfaced in an obvious "not really
/// emailed" banner so the flow can be tested before Gmail SMTP is configured,
/// while making it impossible to mistake for normal behaviour.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String? debugCode;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    this.debugCode,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _codeFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;

  @override
  void initState() {
    super.initState();
    // The whole point of this screen is the code, so put the cursor there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Matches the server's `regex:/^[0-9]{3}\s?[0-9]{3}$/`. Digits-only is
  /// enforced by the input formatter, so anything else here is a length
  /// problem.
  String? _validateCode(String value) {
    final digits = value.replaceAll(RegExp(r'\s'), '');
    if (digits.isEmpty) return 'Please enter the 6-digit code.';
    if (digits.length != 6) return 'The code is 6 digits long.';
    return null;
  }

  /// Min 8 characters, matching `Password::defaults()` and the sign-up screen.
  String? _validatePassword(String value) {
    if (value.isEmpty) return 'Please enter a new password.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }

  String? _validateConfirm(String value) {
    if (value.isEmpty) return 'Please confirm your new password.';
    if (value != _passwordController.text) {
      return 'The two passwords do not match.';
    }
    return null;
  }

  Future<void> _handleReset() async {
    FocusScope.of(context).unfocus();

    final codeError = _validateCode(_codeController.text);
    final passwordError = _validatePassword(_passwordController.text);
    final confirmError = _validateConfirm(_confirmController.text);
    if (codeError != null || passwordError != null || confirmError != null) {
      setState(() {
        _codeError = codeError;
        _passwordError = passwordError;
        _confirmError = confirmError;
      });
      return;
    }

    setState(() => _isLoading = true);
    showFarmSpotLoading(context, message: 'Updating password...');

    final result = await AuthService.resetPasswordWithCode(
      email: widget.email,
      code: _codeController.text,
      password: _passwordController.text,
    );

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
      // Back to log in, not to home: the reset revoked every session token,
      // so anything behind this screen would be authenticated with a token
      // the server no longer knows.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      showFarmAlert(
        context,
        type: FarmAlertType.success,
        title: 'Password Updated',
        message: 'Your password has been changed. Please log in with your new '
            'password.',
      );
      return;
    }

    if (result.statusCode == 422) {
      // The backend sends a specific message for expired / already used /
      // too many attempts so the user knows whether guessing again is useful.
      final message = result.message ?? 'That code is not correct.';
      if (_mentionsCodeProblem(message)) {
        setState(() => _codeError = message);
      }
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        title: _alertTitleFor(message),
        message: message,
      );
      return;
    }

    if (result.statusCode == 429) {
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        icon: Icons.timer_outlined,
        title: 'Too Many Attempts',
        message: 'Too many attempts. Please wait a minute before trying '
            'again.',
      );
      return;
    }

    showFarmAlert(
      context,
      type: FarmAlertType.error,
      title: 'Something Went Wrong',
      message: 'We could not update your password right now. Please try again '
          'in a moment.',
    );
  }

  bool _mentionsCodeProblem(String message) {
    final lower = message.toLowerCase();
    return lower.contains('code') ||
        lower.contains('attempt') ||
        lower.contains('expired');
  }

  String _alertTitleFor(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('expired')) return 'Code Expired';
    if (lower.contains('too many')) return 'Too Many Attempts';
    if (lower.contains('already')) return 'Code Already Used';
    return 'Check Your Code';
  }

  Future<void> _resendCode() async {
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);
    showFarmSpotLoading(context, message: 'Sending a new code...');

    final result = await AuthService.requestPasswordResetCode(widget.email);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() {
      _isLoading = false;
      // A fresh code invalidates the previous attempt count server-side.
      _codeError = null;
    });

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
      showFarmAlert(
        context,
        type: FarmAlertType.success,
        title: 'New Code Sent',
        message: 'If that email belongs to a FarmSpot account, a fresh code is '
            'on its way. Enter it below.',
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
      message: 'We could not send a new code right now. Please try again in '
          'a moment.',
    );
  }

  Widget _buildDebugCodeBanner() {
    final code = widget.debugCode;
    if (code == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningAmber),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined,
                  size: 18, color: AppColors.warningAmber),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Local test mode - not emailed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            code,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
              color: AppColors.darkGreen,
            ),
          ),
        ],
      ),
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
                    'Reset Your Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code we emailed to\n${widget.email}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildDebugCodeBanner(),
                  FarmSpotTextField(
                    hint: '6-digit code',
                    controller: _codeController,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    errorText: _codeError,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (_) {
                      if (_codeError != null) {
                        setState(() => _codeError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'new password',
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    errorText: _passwordError,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.black45,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  FarmSpotTextField(
                    hint: 'confirm new password',
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    errorText: _confirmError,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.black45,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    onChanged: (_) {
                      if (_confirmError != null) {
                        setState(() => _confirmError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 26),
                  FarmSpotButton(
                    label: _isLoading ? 'Updating...' : 'Set New Password',
                    onPressed: _isLoading ? () {} : () => _handleReset(),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: _isLoading ? () {} : () => _resendCode(),
                    child: const Text(
                      "Didn't get a code? Send again",
                      style: TextStyle(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FarmSpotSwitchLink(
                    question: '----- Changed your mind? -----',
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