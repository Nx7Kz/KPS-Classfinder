import 'package:flutter/material.dart';

import 'api_config.dart';
import 'app_theme.dart';
import 'main_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load();
  await ThemeController.load();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeController.mode.addListener(_onThemeChanged);
    _syncDark();
  }

  @override
  void dispose() {
    ThemeController.mode.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ผู้ใช้เปลี่ยนโหมดธีมของโทรศัพท์ขณะเปิดแอปอยู่ (เมื่อเลือก "ตามระบบ")
  @override
  void didChangePlatformBrightness() => _onThemeChanged();

  bool _computeDark() {
    switch (ThemeController.mode.value) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  void _syncDark() => AppColors.dark = _computeDark();

  void _onThemeChanged() {
    final wasDark = AppColors.dark;
    _syncDark();
    if (wasDark == AppColors.dark && !mounted) return;
    setState(() {});
    _rebuildAll();
  }

  /// สีของแอปอ่านจาก AppColors โดยตรง (ไม่ผ่าน Theme) จึงต้องสั่งให้ทุก widget สร้างใหม่
  /// เพื่อให้เห็นสีใหม่ทันที โดยไม่เสียสถานะหน้าจอ (แท็บ/หน้าที่เปิดอยู่)
  void _rebuildAll() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KPS ClassFinder',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MainNav(),
    );
  }
}
