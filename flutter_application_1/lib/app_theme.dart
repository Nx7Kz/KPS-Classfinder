import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const ink = Color(0xFF0B1C30);
  static const primary = Color(0xFF00503A);
  static const accent = Color(0xFFD89B4A);
  static const background = Color(0xFFF8F9FF);
  static const surface = Colors.white;
  static const muted = Color(0xFF5B6B63);
  static const line = Color(0xFFDBE5DE);
  // ชื่อเดิมเป็น "โทนน้ำเงิน/ทอง" จากธีมก่อนหน้า ตอนนี้ใช้เป็นสี tint ของ
  // primary/accent (เขียวเข้ม/ทอง) แทน คงชื่อไว้เพื่อไม่ต้องแก้ทุกจุดที่เรียกใช้
  static const blueTint = Color(0xFFE1F0E7);
  static const goldTint = Color(0xFFFBEEDC);
}

BoxDecoration appCardDecoration({Color color = AppColors.surface}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(16),
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

/// การ์ดสไตล์มีแถบสีเน้นด้านซ้าย (เหมือนการ์ดตารางเรียนในดีไซน์อ้างอิง)
Widget accentBorderCard({
  required Widget child,
  Color accentColor = AppColors.primary,
  Color color = AppColors.surface,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(color: Color(0x120F172A), blurRadius: 20, offset: Offset(0, 8)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 5, color: accentColor),
          Expanded(child: Padding(padding: padding, child: child)),
        ],
      ),
    ),
  );
}
