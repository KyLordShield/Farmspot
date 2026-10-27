import 'package:flutter/services.dart';

abstract final class MobileNumber {
  static const requiredMessage = 'Please enter your mobile number.';
  static const invalidMessage =
      'Please enter an 11-digit number starting with 09 (e.g. 09171234567).';
  static const duplicateMessage = 'That mobile number is already registered.';

  static String? validate(String value) {
    final number = value.trim();
    if (number.isEmpty) return requiredMessage;
    return RegExp(r'^09[0-9]{9}$').hasMatch(number) ? null : invalidMessage;
  }

  static List<TextInputFormatter> get formatters => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(11),
  ];
}
