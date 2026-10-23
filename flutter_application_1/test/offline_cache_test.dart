import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/offline_cache.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'favorite_rooms': '[]'});
    OfflineCache.offlineSince.value = null;
  });

  test('เก็บและอ่านแคชได้ ไม่มีคีย์ = null', () async {
    expect(await OfflineCache.get('api/buildings'), isNull);
    await OfflineCache.put('api/buildings', '[{"name":"A"}]');
    final entry = await OfflineCache.get('api/buildings');
    expect(entry!.body, '[{"name":"A"}]');
    expect(DateTime.now().difference(entry.at).inSeconds, lessThan(5));
  });

  test('cachedRooms รวมห้องของทุกอาคารที่แคชไว้ และข้ามอาคารที่ยังไม่เคยแคช', () async {
    await OfflineCache.put('api/buildings', jsonEncode([{'name': 'อาคาร A'}, {'name': 'อาคาร B'}, {'name': 'อาคาร C'}]));
    await OfflineCache.put('api/building/${Uri.encodeComponent('อาคาร A')}', jsonEncode([{'room_code': 'A-101'}, {'room_code': 'A-102'}]));
    await OfflineCache.put('api/building/${Uri.encodeComponent('อาคาร B')}', jsonEncode([{'room_code': 'B-201'}]));
    final rooms = await OfflineCache.cachedRooms();
    expect(rooms.map((r) => r['room_code']).toList(), ['A-101', 'A-102', 'B-201']);
  });

  test('ไม่มีรายการอาคารที่แคช = ไม่มีห้องให้ค้นออฟไลน์', () async {
    expect(await OfflineCache.cachedRooms(), isEmpty);
  });

  test('clearAll ลบเฉพาะแคช ไม่แตะห้องโปรดและการตั้งค่า', () async {
    await OfflineCache.put('api/buildings', '[]');
    await OfflineCache.markSynced(images: 7);
    expect(await OfflineCache.lastSync(), isNotNull);
    expect(await OfflineCache.imageCount(), 7);
    OfflineCache.offlineSince.value = DateTime.now();

    await OfflineCache.clearAll();
    expect(await OfflineCache.get('api/buildings'), isNull);
    expect(await OfflineCache.lastSync(), isNull);
    expect(await OfflineCache.imageCount(), 0);
    expect(OfflineCache.offlineSince.value, isNull);
    expect((await SharedPreferences.getInstance()).getString('favorite_rooms'), '[]');
  });

  test('markSynced ไม่ส่งจำนวนรูป = คงค่าจำนวนรูปเดิม', () async {
    await OfflineCache.markSynced(images: 5);
    await OfflineCache.markSynced();
    expect(await OfflineCache.imageCount(), 5);
  });

  group('searchRoomsLocal', () {
    final rooms = [
      {'room_code': 'LH3-201', 'building_name': 'อาคาร ศร.3', 'floor': '2', 'room_type': 'ห้องบรรยาย'},
      {'room_code': 'LH3-2010', 'building_name': 'อาคาร ศร.3', 'floor': '2', 'room_type': 'ห้องบรรยาย'},
      {'room_code': 'KH80-201', 'building_name': 'อาคาร 80 ปี', 'floor': '2', 'room_type': 'ห้องบรรยาย'},
      {'room_code': 'ลิฟต์', 'building_name': 'อาคาร 80 ปี', 'floor': '1', 'room_type': 'ลิฟต์'},
      {'room_code': 'ห้องน้ำ', 'building_name': 'อาคาร ศร.3', 'floor': '1', 'room_type': 'ห้องน้ำ'},
    ];

    test('รหัสตรงเป๊ะขึ้นก่อนรหัสขึ้นต้นด้วยคำค้น และไม่สนตัวพิมพ์เล็ก/ใหญ่', () {
      final result = searchRoomsLocal(rooms, 'lh3-201');
      expect(result.map((r) => r['room_code']).toList(), ['LH3-201', 'LH3-2010']);
    });

    test('ค้นด้วยชื่ออาคารและประเภทห้องได้', () {
      // อันดับเท่ากัน เรียงตามอาคาร ชั้น แล้วรหัสห้อง (เหมือนเซิร์ฟเวอร์): ลิฟต์ชั้น 1 มาก่อน KH80-201 ชั้น 2
      expect(searchRoomsLocal(rooms, '80 ปี').map((r) => r['room_code']).toList(), ['ลิฟต์', 'KH80-201']);
      expect(searchRoomsLocal(rooms, 'ห้องบรรยาย').length, 3);
    });

    test('คำค้นว่างหรือไม่ตรงอะไรเลย = รายการว่าง', () {
      expect(searchRoomsLocal(rooms, '   '), isEmpty);
      expect(searchRoomsLocal(rooms, 'zzz'), isEmpty);
    });
  });

  test('formatSyncTime', () {
    expect(formatSyncTime(DateTime(2026, 10, 24, 9, 5)), '24 ต.ค. 09:05');
  });
}
