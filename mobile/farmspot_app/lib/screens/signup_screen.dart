import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  String? _lastNameError;
  String? _firstNameError;
  String? _emailError;
  String? _mobileError;
  String? _addressError;
  String? _passwordError;
  String? _confirmPasswordError;

  static final _nameRegex =
      RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ .'-]+$");
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _mobileRegex = RegExp(r'^09\d{9}$');

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

  String? _validateLastName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Please enter your last name.';
    if (!_nameRegex.hasMatch(name)) {
      return 'Only letters allowed (e.g. "Dela Cruz").';
    }
    return null;
  }

  String? _validateFirstName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Please enter your first name.';
    if (!_nameRegex.hasMatch(name)) {
      return 'Only letters allowed (e.g. "Maria Jane").';
    }
    return null;
  }

  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Please enter your email.';
    if (!_emailRegex.hasMatch(email)) return 'Please enter a valid email address.';
    return null;
  }

  String? _validateMobile(String value) {
    final mobile = value.trim();
    if (mobile.isEmpty) return 'Please enter your mobile number.';
    if (!_mobileRegex.hasMatch(mobile)) {
      return 'Please enter an 11-digit number starting with 09 (e.g. 09171234567).';
    }
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) return 'Please create a password.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }

  String? _validateConfirmPassword(String value) {
    if (value.isEmpty) return 'Please confirm your password.';
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _handleCreateAccount() async {
    FocusScope.of(context).unfocus();

    final lastNameError = _validateLastName(_lastNameController.text);
    final firstNameError = _validateFirstName(_firstNameController.text);
    final emailError = _validateEmail(_emailController.text);
    final mobileError = _validateMobile(_mobileController.text);
    final passwordError = _validatePassword(_passwordController.text);
    final confirmError =
        _validateConfirmPassword(_confirmPasswordController.text);

    if (lastNameError != null ||
        firstNameError != null ||
        emailError != null ||
        mobileError != null ||
        passwordError != null ||
        confirmError != null) {
      setState(() {
        _lastNameError = lastNameError;
        _firstNameError = firstNameError;
        _emailError = emailError;
        _mobileError = mobileError;
        _passwordError = passwordError;
        _confirmPasswordError = confirmError;
      });
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService.attemptRegister(
      name: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
          .trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _confirmPasswordController.text,
      mobileNumber: _mobileController.text.trim(),
      address: _addressController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
    _handleRegisterError(result);
  }

  void _handleRegisterError(AuthRegisterResult result) {
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

    if (result.statusCode == 422 && result.fieldErrors.isNotEmpty) {
      setState(() {
        _firstNameError = _friendlyFieldError(
            result.fieldErrors, 'USR_NAME', 'first name');
        _emailError = _friendlyFieldError(
            result.fieldErrors, 'USR_EMAIL', 'email');
        _mobileError = _friendlyFieldError(
            result.fieldErrors, 'USR_MOBILE_NUMBER', 'mobile number');
        _addressError = _friendlyFieldError(
            result.fieldErrors, 'address', 'address');
        _passwordError = _friendlyFieldError(
            result.fieldErrors, 'USR_PASSWORD', 'password');
        _confirmPasswordError = result.fieldErrors['USR_PASSWORD_confirmation']
                ?.isNotEmpty ??
            false
            ? 'Passwords do not match.'
            : null;
      });
      return;
    }

    showFarmAlert(
      context,
      type: FarmAlertType.error,
      title: 'Something Went Wrong',
      message: 'Something went wrong on our side. Please try again in a moment.',
    );
  }

  /// Picks the first backend message for [fieldKey] and rewrites the raw
  /// "The USR_EMAIL ..." text into a friendly one-liner for the app's field.
  String? _friendlyFieldError(
      Map<String, List<String>> fieldErrors, String fieldKey, String fieldLabel) {
    final messages = fieldErrors[fieldKey];
    if (messages == null || messages.isEmpty) return null;
    final raw = messages.first.toLowerCase();

    if (fieldKey == 'USR_EMAIL') {
      if (raw.contains('taken') || raw.contains('already')) {
        return 'That email is already registered. Try logging in instead.';
      }
      return 'Please enter a valid email address.';
    }
    if (fieldKey == 'USR_MOBILE_NUMBER') {
      if (raw.contains('taken') || raw.contains('already')) {
        return 'That mobile number is already registered.';
      }
      return 'Please enter a valid mobile number (09XXXXXXXXX).';
    }
    if (fieldKey == 'USR_PASSWORD') {
      if (raw.contains('confirmation')) return 'Passwords do not match.';
      if (raw.contains('least') || raw.contains('characters')) {
        return 'Password must be at least 8 characters.';
      }
      return 'Please choose a stronger password.';
    }
    if (fieldKey == 'USR_NAME') {
      return 'Please check your $fieldLabel — only letters are allowed.';
    }
    return 'Please check your $fieldLabel.';
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
      body: SafeArea(
        // Keep the bottom-most content (the "Log In" switch link) reachable:
        // on gesture/button nav phones the home bar overlaps the last row, so
        // the SafeArea reserves that inset and the extra bottom padding lets
        // the form scroll fully above it. Top inset is left alone — the
        // FarmSpotHeader already reserves the status bar with its own padding.
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewPadding.bottom + 32,
          ),
          child: Column(
            children: [
              const FarmSpotHeader(),
              const SizedBox(height: 8),
              const FarmSpotLogo(size: 190),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FarmSpotTextField(
                            hint: 'Lastname',
                            controller: _lastNameController,
                            errorText: _lastNameError,
                            onChanged: (_) {
                              if (_lastNameError != null) {
                                setState(() => _lastNameError = null);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FarmSpotTextField(
                            hint: 'FirstName',
                            controller: _firstNameController,
                            errorText: _firstNameError,
                            onChanged: (_) {
                              if (_firstNameError != null) {
                                setState(() => _firstNameError = null);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                      hint: 'mobile number',
                      controller: _mobileController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      errorText: _mobileError,
                      onChanged: (_) {
                        if (_mobileError != null) {
                          setState(() => _mobileError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    FarmSpotTextField(
                      hint: 'address',
                      controller: _addressController,
                      errorText: _addressError,
                      onChanged: (_) {
                        if (_addressError != null) {
                          setState(() => _addressError = null);
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
                    const SizedBox(height: 14),
                    FarmSpotTextField(
                      hint: 'confirm password',
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      errorText: _confirmPasswordError,
                      onChanged: (_) {
                        if (_confirmPasswordError != null) {
                          setState(() => _confirmPasswordError = null);
                        }
                      },
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.black45,
                        ),
                        onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 16),
                      const Center(child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )),
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
      ),
    );
  }
}