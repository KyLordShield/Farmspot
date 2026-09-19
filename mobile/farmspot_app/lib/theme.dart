import 'package:flutter/material.dart';

/// Shared colors & styling constants for the FarmSpot UI.
class AppColors {
  static const Color primaryGreen = Color(0xFF1B6B2C);
  static const Color darkGreen = Color(0xFF0F4A1C);
  static const Color lightGreen = Color(0xFF6FCF6F);
  static const Color fieldBorder = Color(0xFFBDBDBD);
  static const Color fieldBackground = Color(0xFFF7F7F7);

  /// Softer, slightly cooler backdrop used by the search "mode" so it reads as
  /// a distinct experience from Home (which sits on pure white).
  static const Color searchBackground = Color(0xFFF4F7F1);

  /// Muted sage green for search subtitles / secondary labels.
  static const Color mutedGreen = Color(0xFF5A8A5C);
}

final ThemeData appTheme = ThemeData(
  primaryColor: AppColors.primaryGreen,
  scaffoldBackgroundColor: Colors.white,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryGreen),
  useMaterial3: true,
);
