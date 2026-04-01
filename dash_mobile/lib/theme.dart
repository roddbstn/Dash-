import 'package:flutter/material.dart';

const double kTabletBreakpoint = 650.0;

class AppColors {
  static const Color primary = Color(0xFF3182F6);
  static const Color primaryLight = Color(0xFFE8F3FF);
  static const Color bg = Color(0xFFECEEF0);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textMain = Color(0xFF222222);
  static const Color textSub = Color(0xFF4E5968);
  static const Color border = Color(0xFFE5E8EB);
  static const Color danger = Color(0xFFFF4D4F);
  static const Color success = Color(0xFF00C471);
  static const Color successLight = Color(0xFFE6F9F1);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        surface: AppColors.card,
      ),
      fontFamily: 'Pretendard',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.textMain,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
          letterSpacing: -0.4,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textMain,
          letterSpacing: -0.4,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppColors.textSub,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}
