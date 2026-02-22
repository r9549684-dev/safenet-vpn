import 'package:flutter/material.dart';

class AppTheme {
  static const Color bg = Color(0xFF050810);
  static const Color surface = Color(0xFF0F172A);
  static const Color card = Color(0xFF1E293B);
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);
  static const Color border = Color(0x14FFFFFF);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    fontFamily: 'SF Pro Display',
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: success,
      surface: surface,
      error: error,
    ),
  );
}
