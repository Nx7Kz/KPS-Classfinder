import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// ข้อผิดพลาดที่มีข้อความภาษาไทยพร้อมแสดงให้ผู้ใช้เห็นได้เลย
class ApiException implements Exception {
  final String message;
  final bool isConnection;

  const ApiException(this.message, {this.isConnection = false});

  @override
  String toString() => message;
}

class FloorPlan {
  final String imageUrl;
  final double aspectRatio;

  const FloorPlan({required this.imageUrl, required this.aspectRatio});
}

class Api {
  const Api._();

  static const _timeout = Duration(seconds: 10);

  static Future<http.Response> _get(String path, [Map<String, String>? query]) async {
    var uri = ApiConfig.endpoint(path);
    if (query != null) uri = uri.replace(queryParameters: query);

    try {
      return await http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'เซิร์ฟเวอร์ตอบสนองช้าเกินไป ลองใหม่อีกครั้ง',
        isConnection: true,
      );
    } catch (_) {
      throw const ApiException(
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบอินเทอร์เน็ตหรือที่อยู่เซิร์ฟเวอร์ในหน้าตั้งค่า',
        isConnection: true,
      );
    }
  }

  static dynamic _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw ApiException('เซิร์ฟเวอร์ตอบกลับผิดพลาด (${response.statusCode})');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('รูปแบบข้อมูลจากเซิร์ฟเวอร์ไม่ถูกต้อง');
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic decoded) {
    if (decoded is! List) throw const ApiException('รูปแบบข้อมูลจากเซิร์ฟเวอร์ไม่ถูกต้อง');
    return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  static Future<List<Map<String, dynamic>>> buildings() async {
    return _asList(_decode(await _get('api/buildings')));
  }

  /// วันปิดทำการพิเศษที่ยังไม่สิ้นสุด (ทั้งมหาวิทยาลัย/อาคาร/ห้อง)
  static Future<List<Map<String, dynamic>>> closures() async {
    return _asList(_decode(await _get('api/closures')));
  }

  static Future<List<Map<String, dynamic>>> roomsInBuilding(String buildingName) async {
    return _asList(_decode(await _get('api/building/${Uri.encodeComponent(buildingName)}')));
  }

  static Future<List<Map<String, dynamic>>> searchRooms(String query) async {
    return _asList(_decode(await _get('api/rooms/search', {'q': query})));
  }

  /// คืน null เมื่อชั้นนั้นยังไม่มีแผนที่ (404) แต่ถ้าเชื่อมต่อไม่ได้จะโยน ApiException
  static Future<FloorPlan?> floorPlan(String building, String floor) async {
    final response = await _get('api/floorplan', {'building': building, 'floor': floor});
    if (response.statusCode == 404) return null;

    final decoded = _decode(response);
    if (decoded is! Map) return null;

    final path = decoded['image']?.toString();
    final width = double.tryParse('${decoded['width']}');
    final height = double.tryParse('${decoded['height']}');
    if (path == null || width == null || height == null || height == 0) return null;

    return FloorPlan(
      imageUrl: ApiConfig.endpoint(path).toString(),
      aspectRatio: width / height,
    );
  }

  static Future<List<Map<String, dynamic>>> panoramas(Object roomId) async {
    return _asList(_decode(await _get('api/rooms/$roomId/panoramas')));
  }

  /// อาคารที่มีจุดเดินชม 360° แล้ว (แท็บ "เดินชม")
  static Future<List<Map<String, dynamic>>> tourBuildings() async {
    return _asList(_decode(await _get('api/tour/buildings')));
  }

  /// ข้อมูลห้องจากรหัสห้อง (ใช้ตอนแตะป้ายห้องในหน้าเดินชม) คืน null ถ้าไม่พบ
  static Future<Map<String, dynamic>?> roomByCode(String code) async {
    final response = await _get('api/search/${Uri.encodeComponent(code)}');
    if (response.statusCode == 404) return null;
    final decoded = _decode(response);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  static String assetUrl(String path) => ApiConfig.endpoint(path).toString();

  /// ทดสอบว่าเซิร์ฟเวอร์ที่ระบุตอบกลับได้ ใช้ในหน้าตั้งค่า
  static Future<void> ping(String baseUrl) async {
    final uri = Uri.parse('${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/buildings');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        throw ApiException('เซิร์ฟเวอร์ตอบกลับผิดพลาด (${response.statusCode})');
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('เซิร์ฟเวอร์ไม่ตอบสนอง', isConnection: true);
    } catch (_) {
      throw const ApiException('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้', isConnection: true);
    }
  }
}
