import 'package:flutter/material.dart';

// Inlined from garage_core's "Dusk" design system.
class AppColors {
  static const surface0 = Color(0xFF0A0A0A);
  static const surface1 = Color(0xFF141414);
  static const surface2 = Color(0xFF1C1C1C);
  static const surface3 = Color(0xFF242424);

  static const fg0 = Color(0xFFF5F5F4);
  static const fg1 = Color(0xFFC7C7C5);
  static const fg2 = Color(0xFF8A8A87);
  static const fg3 = Color(0xFF5C5C59);
  static const fg4 = Color(0xFF3A3A37);

  static const textPrimary = fg0;
  static const textSecondary = fg2;
  static const textMuted = fg3;

  static const borderSoft = Color(0x0FFFFFFF);
  static const borderMedium = Color(0x1AFFFFFF);
  static const borderStrong = Color(0x2EFFFFFF);
  static const border = borderSoft;
  static const borderHover = borderMedium;

  static const statusToday = Color(0xFFF08A3E);
  static const statusWeek = Color(0xFFD4A93A);
  static const statusOther = Color(0xFF6B6B68);
  static const statusDone = Color(0xFF4A8A5C);

  static const coral = statusToday;
  static const gold = statusWeek;
  static const emerald = statusDone;
  static const accentMuted = statusOther;
}

const Cubic kAppEase = Cubic(0.22, 1, 0.36, 1);

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.surface0,
    canvasColor: AppColors.surface0,
    dividerColor: AppColors.border,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.gold,
      selectionColor: Color(0x47D4A93A),
      selectionHandleColor: AppColors.gold,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.55),
      bodySmall: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
  );
}
