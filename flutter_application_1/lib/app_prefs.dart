import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ตัวเลือกการแสดงผลที่ผู้ใช้ตั้งเองและเก็บถาวรในเครื่อง (ธีมสีอยู่ใน ThemeController)
class AppPrefs {
  const AppPrefs._();

  static const _labelsKey = 'always_show_labels';
  static const _largeKey = 'map_label_large';

  /// true = แสดงป้ายรหัสห้องบนแผนที่ตลอดเวลา (ไม่รอซูมเข้า)
  static final ValueNotifier<bool> alwaysShowLabels = ValueNotifier<bool>(false);

  /// true = ป้ายรหัสห้องบนแผนที่ใช้ตัวอักษรใหญ่ขึ้น
  static final ValueNotifier<bool> mapLabelLarge = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      alwaysShowLabels.value = prefs.getBool(_labelsKey) ?? false;
      mapLabelLarge.value = prefs.getBool(_largeKey) ?? false;
    } catch (_) {
      // อ่านไม่ได้ก็ใช้ค่าเริ่มต้น
    }
  }

  static Future<void> setAlwaysShowLabels(bool value) async {
    alwaysShowLabels.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_labelsKey, value);
    } catch (_) {}
  }

  static Future<void> setMapLabelLarge(bool value) async {
    mapLabelLarge.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_largeKey, value);
    } catch (_) {}
  }
}
