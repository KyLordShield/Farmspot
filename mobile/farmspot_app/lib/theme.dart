import 'package:flutter/material.dart';

/// Shared colors & styling constants for the FarmSpot UI.
class AppColors {
  static const Color primaryGreen = Color(0xFF1B6B2C);
  static const Color darkGreen = Color(0xFF0F4A1C);
  static const Color lightGreen = Color(0xFF6FCF6F);
  static const Color fieldBorder = Color(0xFFBDBDBD);
  static const Color fieldBackground = Color(0xFFF7F7F7);
}

final ThemeData appTheme = ThemeData(
  primaryColor: AppColors.primaryGreen,
  scaffoldBackgroundColor: Colors.white,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryGreen),
  useMaterial3: true,
);
