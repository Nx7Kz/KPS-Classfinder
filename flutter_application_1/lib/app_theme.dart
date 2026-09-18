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

/// แถบหัวแอปแบบ sticky ด้านบนสุด (ไอคอน + ชื่อแอป) ใช้ร่วมกันทุกแท็บ
class AppHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const AppHeaderBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.school_rounded, color: AppColors.primary, size: 24),
          const SizedBox(width: 8),
          Text(
            'KPS ClassFinder',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
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
