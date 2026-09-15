import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const ink = Color(0xFF172033);
  static const primary = Color(0xFF304B7A);
  static const accent = Color(0xFFD89B4A);
  static const background = Color(0xFFF6F7FB);
  static const surface = Colors.white;
  static const muted = Color(0xFF667085);
  static const line = Color(0xFFE7EAF0);
  static const blueTint = Color(0xFFEAF0FF);
  static const goldTint = Color(0xFFFFF2DC);
}

BoxDecoration appCardDecoration({Color color = AppColors.surface}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: AppColors.line),
    boxShadow: const [
      BoxShadow(
        color: Color(0x120F172A),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
    ],
  );
}
