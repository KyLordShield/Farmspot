import '../legal/legal.dart';
import 'package:flutter/material.dart';
import 'package:farmspot_app/utils/input_limits.dart';
import 'package:farmspot_app/utils/mobile_number.dart';
import '../widgets/common_widgets.dart';
import '../widgets/password_requirements.dart';
import '../widgets/address_area_picker.dart';
import '../widgets/lottie_loader.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  bool _forward = true;
  final _scrollController = ScrollController();
  late final _slideController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _checkingLegal = false, _legalAccepted = false;
  LegalCatalog? _legalCatalog;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  String? _lastNameError;
  String? _firstNameError;
  String? _emailError;
  String? _mobileError;
  String? _addressError;
  String? _passwordError;
  String? _confirmPasswordError;

  static final _nameRegex = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ .'-]+$");
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _slideController.dispose();
    _scrollController.dispose();
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
    if (!_emailRegex.hasMatch(email))
      return 'Please enter a valid email address.';
    return null;
  }

  String? _validateMobile(String value) => MobileNumber.validate(value);

  String? _validatePassword(String value) {
    return PasswordRequirements.validate(value);
  }

  String? _validateConfirmPassword(String value) {
    if (value.isEmpty) return 'Please confirm your password.';
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _handleCreateAccount() async {
    if (_isLoading || _checkingLegal) return;
    _checkingLegal = true;
    late LegalCatalog catalog;
    try {
      catalog = _legalCatalog ?? await LegalService.catalog();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load the legal pages. Please reopen the app and try again.',
            ),
          ),
        );
      return;
    } finally {
      _checkingLegal = false;
    }
    if (!mounted) return;
    if (catalog.published && !_legalAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please review and accept the Terms of Service and acknowledge the Privacy Policy.',
          ),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();

    final lastNameError = _validateLastName(_lastNameController.text);
    var firstNameError = _validateFirstName(_firstNameController.text);
    if ('${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim()
            .length >
        InputLimits.fullName) {
      firstNameError =
          'Full name must be ${InputLimits.fullName} characters or fewer.';
    }
    final emailError = _validateEmail(_emailController.text);
    final mobileError = _validateMobile(_mobileController.text);
    final passwordError = _validatePassword(_passwordController.text);
    final confirmError = _validateConfirmPassword(
      _confirmPasswordController.text,
    );

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
      if (lastNameError != null || firstNameError != null) {
        _goToStep(0);
      } else if (emailError != null || mobileError != null) {
        _goToStep(1);
      }
      return;
    }

    setState(() => _isLoading = true);
    showFarmLottieLoading(context, message: 'Creating account...');

    final result = await AuthService.attemptRegister(
      name:
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _confirmPasswordController.text,
      mobileNumber: _mobileController.text.trim(),
      address: _addressController.text.trim(),
      legalAcceptance: catalog.published
          ? {
              'legal_version': catalog.version,
              'terms_accepted': '1',
              'privacy_acknowledged': '1',
            }
          : null,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _isLoading = false);

    if (result.success) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
        message:
            "We couldn't reach FarmSpot. Please check your internet "
            'connection and try again.',
        buttonLabel: 'Try Again',
      );
      return;
    }

    if (result.fieldErrors.keys.any(
      (key) => [
        'legal_version',
        'terms_accepted',
        'privacy_acknowledged',
      ].contains(key),
    )) {
      showFarmAlert(
        context,
        type: FarmAlertType.error,
        title: 'Review the Legal Pages',
        message: result.fieldErrors.values
            .expand((messages) => messages)
            .join('\n'),
      );
      return;
    }
    if (result.fieldErrors.isNotEmpty) {
      setState(() {
        _firstNameError = _friendlyFieldError(
          result.fieldErrors,
          'USR_NAME',
          'first name',
        );
        _emailError = _friendlyFieldError(
          result.fieldErrors,
          'USR_EMAIL',
          'email',
        );
        _mobileError = _friendlyFieldError(
          result.fieldErrors,
          'USR_MOBILE_NUMBER',
          'mobile number',
        );
        _addressError = _friendlyFieldError(
          result.fieldErrors,
          'address',
          'address',
        );
        _passwordError = _friendlyFieldError(
          result.fieldErrors,
          'USR_PASSWORD',
          'password',
        );
        _confirmPasswordError =
            result.fieldErrors['USR_PASSWORD_confirmation']?.isNotEmpty ?? false
            ? 'Passwords do not match.'
            : null;
      });
      if (_firstNameError != null) {
        _goToStep(0);
      } else if (_emailError != null ||
          _mobileError != null ||
          _addressError != null) {
        _goToStep(1);
      }
      final messages = <String?>[
        _firstNameError,
        _emailError,
        _mobileError,
        _addressError,
        _passwordError,
        _confirmPasswordError,
      ].whereType<String>().toSet().toList();
      showFarmAlert(
        context,
        type: FarmAlertType.error,
        title: 'Check Your Details',
        message: messages.isEmpty
            ? 'Please check your registration details and try again.'
            : messages.join('\n'),
        buttonLabel: 'Review Details',
      );
      return;
    }

    if (result.statusCode == 422 ||
        result.statusCode == 409 ||
        result.statusCode == 429) {
      showFarmAlert(
        context,
        type: FarmAlertType.error,
        title: result.statusCode == 429 ? 'Please Wait' : 'Check Your Details',
        message: result.statusCode == 429
            ? 'Too many attempts. Please wait a moment before trying again.'
            : result.statusCode == 409
            ? 'An account with these details already exists. Check your email and mobile number, or try logging in.'
            : 'Please check your registration details and try again.',
      );
      return;
    }

    showFarmAlert(
      context,
      type: FarmAlertType.error,
      title: 'Something Went Wrong',
      message:
          'Something went wrong on our side. Please try again in a moment.',
    );
  }

  /// Picks the first backend message for [fieldKey] and rewrites the raw
  /// "The USR_EMAIL ..." text into a friendly one-liner for the app's field.
  String? _friendlyFieldError(
    Map<String, List<String>> fieldErrors,
    String fieldKey,
    String fieldLabel,
  ) {
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
        return MobileNumber.duplicateMessage;
      }
      return MobileNumber.invalidMessage;
    }
    if (fieldKey == 'USR_PASSWORD') {
      if (raw.contains('confirmation')) return 'Passwords do not match.';
      if (raw.contains('uppercase') ||
          raw.contains('lowercase') ||
          raw.contains('number')) {
        return 'Include an uppercase letter, a lowercase letter, and a number.';
      }
      if (raw.contains('least') || raw.contains('characters')) {
        return 'Password must be at least 8 characters.';
      }
      return 'Please choose a stronger password.';
    }
    if (fieldKey == 'USR_NAME') {
      if (raw.contains('characters') || raw.contains('greater'))
        return 'Full name must be ${InputLimits.fullName} characters or fewer.';
      return 'Please check your $fieldLabel — only letters are allowed.';
    }
    if (fieldKey == 'address' &&
        (raw.contains('characters') || raw.contains('greater'))) {
      return 'Address must be ${InputLimits.address} characters or fewer.';
    }
    return 'Please check your $fieldLabel.';
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(farmFadeRoute(const LoginScreen()));
  }

  void _goToStep(int step) {
    if (_isLoading || step == _step) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _forward = step > _step;
      _step = step;
    });
    _slideController.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _nextStep() {
    if (_slideController.isAnimating || _isLoading) return;
    if (_step == 0) {
      setState(() {
        _firstNameError = _validateFirstName(_firstNameController.text);
        _lastNameError = _validateLastName(_lastNameController.text);
      });
      if (_firstNameError != null || _lastNameError != null) return;
    } else if (_step == 1) {
      setState(() {
        _emailError = _validateEmail(_emailController.text);
        _mobileError = _validateMobile(_mobileController.text);
      });
      if (_emailError != null || _mobileError != null) return;
    }
    _goToStep(_step + 1);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  Widget _nameStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label('First name'),
      FarmSpotTextField(
        hint: 'FirstName',
        controller: _firstNameController,
        maxLength: InputLimits.personNamePart,
        showCounter: false,
        errorText: _firstNameError,
        onChanged: (_) => setState(() => _firstNameError = null),
      ),
      const SizedBox(height: 18),
      _label('Last name'),
      FarmSpotTextField(
        hint: 'Lastname',
        controller: _lastNameController,
        maxLength: InputLimits.personNamePart,
        showCounter: false,
        errorText: _lastNameError,
        onChanged: (_) => setState(() => _lastNameError = null),
      ),
    ],
  );

  Widget _contactStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label('Email'),
      FarmSpotTextField(
        hint: 'email',
        controller: _emailController,
        maxLength: 200,
        showCounter: false,
        keyboardType: TextInputType.emailAddress,
        errorText: _emailError,
        onChanged: (_) => setState(() => _emailError = null),
      ),
      const SizedBox(height: 18),
      _label('Mobile number'),
      FarmSpotTextField(
        hint: 'mobile number',
        controller: _mobileController,
        keyboardType: TextInputType.phone,
        inputFormatters: MobileNumber.formatters,
        errorText: _mobileError,
        onChanged: (_) => setState(() => _mobileError = null),
      ),
      const SizedBox(height: 18),
      _label('Address (optional)'),
      AddressAreaField(
        controller: _addressController,
        maxLength: InputLimits.address,
        onChanged: (_) => setState(() => _addressError = null),
        fieldBuilder: (focusNode) => FarmSpotTextField(
          hint: 'address',
          focusNode: focusNode,
          controller: _addressController,
          showCounter: false,
          maxLength: InputLimits.address,
          errorText: _addressError,
          onChanged: (_) => setState(() => _addressError = null),
        ),
      ),
    ],
  );

  Widget _passwordStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label('Password'),
      FarmSpotTextField(
        hint: 'password',
        controller: _passwordController,
        obscureText: _obscurePassword,
        errorText: _passwordError,
        onChanged: (_) => setState(() => _passwordError = null),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.black45,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      PasswordRequirements(controller: _passwordController),
      const SizedBox(height: 18),
      _label('Confirm password'),
      FarmSpotTextField(
        hint: 'confirm password',
        controller: _confirmPasswordController,
        obscureText: _obscureConfirm,
        errorText: _confirmPasswordError,
        onChanged: (_) => setState(() => _confirmPasswordError = null),
        suffixIcon: IconButton(
          tooltip: _obscureConfirm ? 'Show confirmation' : 'Hide confirmation',
          icon: Icon(
            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
            color: Colors.black45,
          ),
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      const SizedBox(height: 20),
      LegalRegistrationConsent(
        onChanged: (catalog, accepted) {
          _legalCatalog = catalog;
          _legalAccepted = accepted;
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    const titles = ['Your name', 'Contact details', 'Secure your account'];
    const descriptions = [
      'Tell us what to call you.',
      'Add your email, mobile number and address.',
      'Create a password and review the agreement.',
    ];
    final steps = [_nameStep(), _contactStep(), _passwordStep()];
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _step > 0) _goToStep(_step - 1);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (_step > 0) {
                                _goToStep(_step - 1);
                              } else {
                                _goToLogin();
                              }
                            },
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(
                      child: Text(
                        'Create your account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Center(child: FarmSpotLogo(size: 110)),
                const SizedBox(height: 20),
                Text(
                  'Step ${_step + 1} of 3',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var index = 0; index < 3; index++) ...[
                      if (index > 0) const SizedBox(width: 6),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: index <= _step
                                ? const Color(0xFF00664E)
                                : const Color(0xFFE7ECE9),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  titles[_step],
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  descriptions[_step],
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                SlideTransition(
                  key: const Key('signup-slide'),
                  position:
                      Tween<Offset>(
                            begin: Offset(_forward ? .12 : -.12, 0),
                            end: Offset.zero,
                          )
                          .chain(CurveTween(curve: Curves.easeOutCubic))
                          .animate(_slideController),
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      for (var index = 0; index < steps.length; index++)
                        Offstage(
                          offstage: index != _step,
                          child: TickerMode(
                            enabled: index == _step,
                            child: ExcludeFocus(
                              excluding: index != _step,
                              child: KeyedSubtree(
                                key: ValueKey('signup-step-$index'),
                                child: steps[index],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                FarmSpotButton(
                  label: _step < 2
                      ? 'Next'
                      : _isLoading
                      ? 'Creating Account...'
                      : 'Create Account',
                  trailingIcon: Icons.arrow_forward,
                  onPressed: _isLoading
                      ? () {}
                      : _step < 2
                      ? _nextStep
                      : _handleCreateAccount,
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
        ),
      ),
    );
  }
}
