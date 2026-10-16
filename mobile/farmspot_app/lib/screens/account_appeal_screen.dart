import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// The re-evaluation form for an account an admin took down.
///
/// Reached from the login screen after a 403 `ACCOUNT_TAKEN_DOWN`. Login was
/// refused, so there is no session: the user re-proves ownership with the same
/// email and password they just typed, the backend checks both, and only then
/// does it open an appeal. The email is prefilled (they just typed it) but left
/// editable in case they switched accounts; the password is never prefilled.
class AccountAppealScreen extends StatefulWidget {
  /// The email the user attempted to sign in with.
  final String email;

  /// The admin's takedown reason, shown up top so the request answers a real
  /// accusation rather than guessing at one.
  final String? takedownReason;

  const AccountAppealScreen({
    super.key,
    required this.email,
    this.takedownReason,
  });

  @override
  State<AccountAppealScreen> createState() => _AccountAppealScreenState();
}

class _AccountAppealScreenState extends State<AccountAppealScreen> {
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  final _reasonController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  String? _reasonError;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Please enter your email.';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!valid) return 'Please enter a valid email address.';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final emailError = _validateEmail(_emailController.text);
    final passwordError =
        _passwordController.text.isEmpty ? 'Please enter your password.' : null;
    final reasonError = _reasonController.text.trim().isEmpty
        ? 'Please explain why your account should be restored.'
        : null;

    if (emailError != null || passwordError != null || reasonError != null) {
      setState(() {
        _emailError = emailError;
        _passwordError = passwordError;
        _reasonError = reasonError;
      });
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService.submitAccountAppeal(
      email: _emailController.text,
      password: _passwordController.text,
      reason: _reasonController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      await showFarmAlert(
        context,
        type: FarmAlertType.success,
        title: 'Request Sent',
        message: 'Your request is with the Association. You will be notified '
            'once it has been reviewed.',
        buttonLabel: 'OK',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    if (result.isNetworkError) {
      await showFarmAlert(
        context,
        type: FarmAlertType.error,
        icon: Icons.wifi_off_rounded,
        title: 'No Connection',
        message: "We couldn't reach FarmSpot. Please check your internet "
            'connection and try again.',
      );
      return;
    }

    // 401 = email/password do not match; 403 = not a takedown (nothing to
    // appeal); 422 = already pending or a previous denial still stands; 429 =
    // throttled. The backend message already says which, so show it verbatim.
    await showFarmAlert(
      context,
      type: FarmAlertType.warning,
      title: 'Could Not Send Request',
      message: result.message ?? 'Please try again in a moment.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Re-evaluation'),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your account has been taken down',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'You can ask the Association to look at this decision again. '
                'Confirm your details and tell us why it should be restored.',
                style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
              ),
              if ((widget.takedownReason ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason given:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(widget.takedownReason!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FarmSpotTextField(
                hint: 'email',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
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
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.black45,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 14),
              FarmSpotTextField(
                hint: 'Why should your account be restored?',
                controller: _reasonController,
                errorText: _reasonError,
                onChanged: (_) {
                  if (_reasonError != null) setState(() => _reasonError = null);
                },
              ),
              const SizedBox(height: 24),
              FarmSpotButton(
                label: _isLoading ? 'Sending...' : 'Send Request',
                onPressed: _isLoading ? () {} : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
