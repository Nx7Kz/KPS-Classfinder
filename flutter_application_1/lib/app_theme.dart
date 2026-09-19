import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// โทนเขียว-ขาวแบบมินิมอล: พื้นขาว เส้นขอบบาง ไม่ใช้เงาหนัก มีสีเขียวเป็นสีเดียวที่เด่น
/// มีโหมดมืดด้วย: สีทุกตัวเป็น getter ที่เลือกตามค่า [dark] ปัจจุบัน
/// (ตั้งโดย ThemeController และสั่งสร้าง UI ใหม่ทั้งแอปเมื่อสลับ)
class AppColors {
  const AppColors._();

  /// true เมื่อกำลังแสดงโหมดมืด
  static bool dark = false;

  static Color _pick(Color light, Color darkColor) => dark ? darkColor : light;

  static Color get primary => _pick(const Color(0xFF15803D), const Color(0xFF4ADE80));
  // สีเขียวเข้มขึ้น (หมุดที่ถูกเลือก) ในโหมดมืดใช้เขียวอ่อนเพื่อให้เด่นบนพื้นมืด
  static Color get primaryDark => _pick(const Color(0xFF0F5C2B), const Color(0xFFA7F3D0));
  static Color get onPrimary => _pick(Colors.white, const Color(0xFF052E16));
  static Color get tint => _pick(const Color(0xFFEAF6EE), const Color(0xFF1B3A2A));
  static Color get background => _pick(Colors.white, const Color(0xFF0D1511));
  static Color get surface => _pick(Colors.white, const Color(0xFF15201A));
  static Color get ink => _pick(const Color(0xFF10241A), const Color(0xFFE6F0EA));
  static Color get muted => _pick(const Color(0xFF66776D), const Color(0xFF9AABA1));
  static Color get line => _pick(const Color(0xFFE3EBE6), const Color(0xFF26352D));
  static Color get fill => _pick(const Color(0xFFF5F9F6), const Color(0xFF1A2720));

  // สีสถานะ ใช้เฉพาะเพื่อสื่อความหมาย (ปิดปรับปรุง / ผิดพลาด)
  static Color get warning => _pick(const Color(0xFFB45309), const Color(0xFFFBBF6A));
  static Color get warningTint => _pick(const Color(0xFFFEF3E2), const Color(0xFF3A2D14));
  static Color get danger => _pick(const Color(0xFFB42318), const Color(0xFFF7877D));
  static Color get dangerTint => _pick(const Color(0xFFFDECEA), const Color(0xFF3A1F1D));
}

/// การตั้งค่าธีม: ตามระบบ / สว่าง / มืด (เก็บถาวรในเครื่อง)
class ThemeController {
  const ThemeController._();

  static const _prefsKey = 'theme_mode';

  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_prefsKey)) {
        case 'light':
          mode.value = ThemeMode.light;
        case 'dark':
          mode.value = ThemeMode.dark;
        default:
          mode.value = ThemeMode.system;
      }
    } catch (_) {
      // อ่านไม่ได้ก็ใช้ตามระบบ
    }
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.name);
    } catch (_) {}
  }
}

ThemeData buildAppTheme() {
  final brightness = AppColors.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF15803D),
    brightness: brightness,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    outline: AppColors.line,
    error: AppColors.danger,
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: AppColors.tint,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? AppColors.primary : AppColors.muted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 11.5,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? AppColors.primary : AppColors.muted, size: 24);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size(0, 50),
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 50),
        side: BorderSide(color: AppColors.line),
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fill,
      hintStyle: TextStyle(color: AppColors.muted, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.danger, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary,
      side: BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      secondaryLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.dark ? const Color(0xFF2A3B31) : const Color(0xFF10241A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary),
  );
}

/// การ์ดแบนราบ: ขอบบาง ไม่มีเงา
BoxDecoration appCardDecoration({Color? color, double radius = 16}) {
  return BoxDecoration(
    color: color ?? AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.line),
  );
}
