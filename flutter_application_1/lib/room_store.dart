import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// เก็บ "รายการโปรด" และ "ห้องที่ค้นหา/ดูล่าสุด" แบบถาวรในเครื่อง
class RoomStore {
  RoomStore._();

  static const _favoritesKey = 'favorite_rooms';
  static const _recentsKey = 'recent_rooms';
  static const _maxRecents = 8;

  static String _roomId(Map<String, dynamic> room) => room['id']?.toString() ?? room['room_code']?.toString() ?? '';

  static Future<List<Map<String, dynamic>>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((room) => Map<String, dynamic>.from(room)).toList();
    } catch (_) {
      return [];
    }
  }

  /// เพิ่มค่าทุกครั้งที่รายการโปรด/ประวัติเปลี่ยน ให้หน้าที่แสดงรายการฟังแล้วโหลดใหม่
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> _save(String key, List<Map<String, dynamic>> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(rooms));
    revision.value++;
  }

  static Future<List<Map<String, dynamic>>> loadFavorites() => _load(_favoritesKey);

  static Future<List<Map<String, dynamic>>> loadRecents() => _load(_recentsKey);

  static Future<bool> isFavorite(Map<String, dynamic> room) async {
    final favorites = await loadFavorites();
    final id = _roomId(room);
    return favorites.any((item) => _roomId(item) == id);
  }

  /// สลับสถานะรายการโปรด แล้วคืนสถานะล่าสุดหลังสลับ (true = เป็นรายการโปรดแล้ว)
  static Future<bool> toggleFavorite(Map<String, dynamic> room) async {
    final favorites = await loadFavorites();
    final id = _roomId(room);
    final alreadyFavorite = favorites.any((item) => _roomId(item) == id);

    if (alreadyFavorite) {
      favorites.removeWhere((item) => _roomId(item) == id);
    } else {
      favorites.insert(0, room);
    }

    await _save(_favoritesKey, favorites);
    return !alreadyFavorite;
  }

  static Future<void> addRecent(Map<String, dynamic> room) async {
    final recents = await loadRecents();
    final id = _roomId(room);

    recents.removeWhere((item) => _roomId(item) == id);
    recents.insert(0, room);

    await _save(_recentsKey, recents.take(_maxRecents).toList());
  }

  static Future<void> clearRecents() => _save(_recentsKey, const []);

  static Future<void> clearFavorites() => _save(_favoritesKey, const []);
}
