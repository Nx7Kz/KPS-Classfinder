import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// แคชข้อมูลจากเซิร์ฟเวอร์ไว้ในเครื่อง ให้แอปยังเปิดดูอาคาร ห้อง และค้นหาได้เมื่อไม่มีอินเทอร์เน็ต
/// เก็บเป็นข้อความ JSON ต่อ 1 คำขอ (คีย์ = path + query) พร้อมเวลาที่เก็บ
class CachedEntry {
  final String body;
  final DateTime at;

  const CachedEntry(this.body, this.at);
}

class OfflineCache {
  const OfflineCache._();

  static const _prefix = 'cache_v1:';
  static const _syncKey = 'cache_last_sync';
  static const _imagesKey = 'cache_image_count';

  /// ไม่ใช่ null เมื่อตอนนี้แอปแสดงข้อมูลจากแคชเพราะเชื่อมต่อเซิร์ฟเวอร์ไม่ได้ (ค่าคือเวลาที่เก็บข้อมูลนั้น)
  static final ValueNotifier<DateTime?> offlineSince = ValueNotifier<DateTime?>(null);

  static Future<void> put(String key, String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'b': body}));
    } catch (_) {
      // เก็บไม่ได้ก็ข้าม (แค่ไม่มีแคช)
    }
  }

  static Future<CachedEntry?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CachedEntry(decoded['b'].toString(), DateTime.fromMillisecondsSinceEpoch(decoded['t'] as int));
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_syncKey);
      return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return null;
    }
  }

  static Future<int> imageCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_imagesKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// บันทึกว่าซิงค์เสร็จ [images] = จำนวนรูปแผนผัง/ปกที่ดาวน์โหลดไว้ (null = ไม่แตะค่าเดิม เช่นซิงค์เฉพาะข้อมูลตัวหนังสือ)
  static Future<void> markSynced({int? images}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_syncKey, DateTime.now().millisecondsSinceEpoch);
      if (images != null) await prefs.setInt(_imagesKey, images);
    } catch (_) {}
  }

  /// ลบข้อมูลที่แคชไว้ทั้งหมด (ไม่แตะห้องโปรด/ประวัติ/การตั้งค่า)
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((key) => key.startsWith(_prefix)).toList()) {
        await prefs.remove(key);
      }
      await prefs.remove(_syncKey);
      await prefs.remove(_imagesKey);
    } catch (_) {}
    offlineSince.value = null;
  }

  /// ห้องทั้งหมดของทุกอาคารที่เคยแคชไว้ ใช้ค้นหาตอนออฟไลน์
  static Future<List<Map<String, dynamic>>> cachedRooms() async {
    final buildingsEntry = await get('api/buildings');
    if (buildingsEntry == null) return const [];
    final result = <Map<String, dynamic>>[];
    try {
      final buildings = jsonDecode(buildingsEntry.body);
      if (buildings is! List) return const [];
      for (final building in buildings.whereType<Map>()) {
        final name = building['name']?.toString();
        if (name == null) continue;
        final entry = await get('api/building/${Uri.encodeComponent(name)}');
        if (entry == null) continue;
        final rooms = jsonDecode(entry.body);
        if (rooms is List) result.addAll(rooms.whereType<Map>().map((room) => Map<String, dynamic>.from(room)));
      }
    } catch (_) {
      return const [];
    }
    return result;
  }
}

/// ค้นห้องจากรายการที่แคชไว้ จัดอันดับแบบเดียวกับเซิร์ฟเวอร์:
/// รหัสห้องตรงเป๊ะ > ขึ้นต้นด้วยคำค้น > มีคำค้น > ตรงชื่ออาคาร > ตรงประเภทห้อง (สูงสุด 50 รายการ)
List<Map<String, dynamic>> searchRoomsLocal(List<Map<String, dynamic>> rooms, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  int? rank(Map<String, dynamic> room) {
    final code = (room['room_code']?.toString() ?? '').toLowerCase();
    final building = (room['building_name']?.toString() ?? '').toLowerCase();
    final type = (room['room_type']?.toString() ?? '').toLowerCase();
    if (code == q) return 0;
    if (code.startsWith(q)) return 1;
    if (code.contains(q)) return 2;
    if (building.contains(q)) return 3;
    if (type.contains(q)) return 4;
    return null;
  }

  final ranked = <(int, Map<String, dynamic>)>[
    for (final room in rooms)
      if (rank(room) case final r?) (r, room),
  ];
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) return byRank;
    final byBuilding = (a.$2['building_name']?.toString() ?? '').compareTo(b.$2['building_name']?.toString() ?? '');
    if (byBuilding != 0) return byBuilding;
    final byFloor = (a.$2['floor']?.toString() ?? '').compareTo(b.$2['floor']?.toString() ?? '');
    if (byFloor != 0) return byFloor;
    return (a.$2['room_code']?.toString() ?? '').compareTo(b.$2['room_code']?.toString() ?? '');
  });
  return [for (final entry in ranked.take(50)) entry.$2];
}

const _months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

/// "24 ต.ค. 16:30" (เวลาท้องถิ่นของเครื่อง)
String formatSyncTime(DateTime at) {
  final local = at.toLocal();
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '${local.day} ${_months[local.month - 1]} $time';
}
