import 'package:flutter/material.dart';
import '../theme.dart';

class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({super.key, required this.controller});
  final TextEditingController controller;

  static Map<String, bool> checks(String value) => {
    'At least 8 characters': value.runes.length >= 8,
    'One uppercase letter (A–Z)': RegExp(r'[A-Z]').hasMatch(value),
    'One lowercase letter (a–z)': RegExp(r'[a-z]').hasMatch(value),
    'One number (0–9)': RegExp(r'[0-9]').hasMatch(value),
  };

  static String? validate(String value) {
    if (value.isEmpty) return 'Please create a password.';
    if (value.runes.length < 8)
      return 'Password must be at least 8 characters.';
    if (checks(value).values.any((met) => !met)) {
      return 'Include an uppercase letter, a lowercase letter, and a number.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final check in checks(value.text).entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        check.value
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: check.value
                            ? AppColors.primaryGreen
                            : Colors.black45,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          check.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: check.value
                                ? AppColors.primaryGreen
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
