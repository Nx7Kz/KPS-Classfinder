import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ที่อยู่เซิร์ฟเวอร์ของแอป เปลี่ยนได้ตอนรันจากหน้า "ตั้งค่า" (เก็บถาวรในเครื่อง)
/// ลำดับความสำคัญ: ค่าที่ผู้ใช้ตั้งไว้ > --dart-define=API_BASE_URL > ค่าเริ่มต้นตามแพลตฟอร์ม
class ApiConfig {
  const ApiConfig._();

  static const _prefsKey = 'api_base_url';
  static const _envUrl = String.fromEnvironment('API_BASE_URL');

  static String _baseUrl = defaultUrl;

  /// Android emulator เรียกเครื่องโฮสต์ผ่าน 10.0.2.2 ส่วนแพลตฟอร์มอื่นใช้ localhost
  static String get defaultUrl {
    if (_envUrl.isNotEmpty) return _normalize(_envUrl);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static String get baseUrl => _baseUrl;

  static String _normalize(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

  /// อ่านค่าที่บันทึกไว้ ต้องเรียกก่อน runApp
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.trim().isNotEmpty) _baseUrl = _normalize(saved);
    } catch (_) {
      // อ่านไม่ได้ก็ใช้ค่าเริ่มต้น
    }
  }

  /// true ถ้าเป็น URL แบบ http/https ที่มีชื่อโฮสต์
  static bool isValid(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  static Future<void> save(String url) async {
    _baseUrl = _normalize(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _baseUrl);
  }

  static Future<void> reset() async {
    _baseUrl = defaultUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Uri endpoint(String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$_baseUrl/$clean');
  }
}
