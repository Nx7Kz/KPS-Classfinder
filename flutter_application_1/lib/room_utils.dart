/// ฟังก์ชันช่วยจัดการข้อมูลห้อง/ชั้นที่ใช้ร่วมกันหลายหน้า
library;

import 'package:flutter/material.dart' show IconData, Icons;

/// เรียงชั้น: ตัวเลขก่อน (น้อย→มาก) ตามด้วยชื่อชั้นอื่นตามตัวอักษร
List<String> sortFloors(Iterable<String> floors) {
  final list = floors.toSet().toList();
  list.sort((a, b) {
    final an = int.tryParse(a);
    final bn = int.tryParse(b);
    if (an != null && bn != null) return an.compareTo(bn);
    if (an != null) return -1;
    if (bn != null) return 1;
    return a.compareTo(b);
  });
  return list;
}

String floorOf(Map<String, dynamic> room) => room['floor']?.toString() ?? '-';

String floorLabel(String floor) {
  if (floor == '-' || floor.isEmpty) return 'ไม่ระบุชั้น';
  return int.tryParse(floor) != null ? 'ชั้น $floor' : floor;
}

bool isMaintenance(Map<String, dynamic> room) => room['status']?.toString() == 'maintenance';

/// งดใช้งาน = ผู้ดูแลระบุว่าห้องใช้ไม่ได้ชั่วคราว (ต่างจากปิดปรับปรุง) พร้อมสาเหตุ (ถ้ามี)
bool isSuspended(Map<String, dynamic> room) => room['status']?.toString() == 'suspended';

/// ห้องที่ผู้ดูแลตั้งสถานะว่าใช้งานไม่ได้อยู่ (ปิดปรับปรุงหรืองดใช้งาน)
bool isUnavailable(Map<String, dynamic> room) => isMaintenance(room) || isSuspended(room);

/// สาเหตุของสถานะห้อง (เช่น "ซ่อมเครื่องปรับอากาศ") คืน null ถ้าไม่ได้ระบุ
String? statusReasonOf(Map<String, dynamic> room) {
  final reason = room['status_reason']?.toString().trim();
  return reason == null || reason.isEmpty ? null : reason;
}

/// คำในประเภท/รหัสห้องที่นับเป็น "สิ่งอำนวยความสะดวก" (ไม่ใช่ห้องเรียน) ต้องตรงกับ FACILITY_WORDS ใน kps_backend/server.js
const kFacilityWords = ['ห้องน้ำ', 'ลิฟต์', 'บันได', 'โถง', 'ร้านค้า', 'โรงอาหาร', 'สำนักงาน', 'ห้องสมุด', 'อ่านหนังสือ'];

/// ห้องน้ำ ลิฟต์ บันได โถง ร้านค้า สำนักงาน ห้องสมุด ฯลฯ ห้องที่ไม่ระบุประเภทนับเป็นห้องเรียน
bool isFacilityRoom(Map<String, dynamic> room) {
  final text = '${room['room_type'] ?? ''} ${room['room_code'] ?? ''}';
  return kFacilityWords.any(text.contains);
}

/// จำนวนห้องเรียนของอาคาร: ใช้ค่าจากเซิร์ฟเวอร์ ถ้าไม่มี (เซิร์ฟเวอร์รุ่นเก่า) ใช้จำนวนห้องทั้งหมด
int classroomCountOf(Map<String, dynamic> building) =>
    int.tryParse('${building['classroom_count']}') ?? int.tryParse('${building['room_count']}') ?? 0;

/// ไอคอนตามประเภทห้อง (ลิฟต์ ห้องน้ำ ห้องบรรยาย ฯลฯ) ใช้บนการ์ดห้อง ถ้าไม่รู้จักประเภทใช้ไอคอนประตู
IconData roomIcon(Map<String, dynamic> room) {
  final text = '${room['room_type'] ?? ''} ${room['room_code'] ?? ''}';
  bool has(String word) => text.contains(word);
  if (has('ห้องน้ำ')) return Icons.wc_rounded;
  if (has('ลิฟต์')) return Icons.elevator_rounded;
  if (has('ห้องบรรยาย')) return Icons.co_present_rounded;
  if (has('ปฏิบัติการ') || has('Lab')) return Icons.science_rounded;
  if (has('คอมพิวเตอร์')) return Icons.computer_rounded;
  if (has('ประชุม') || has('สัมมนา')) return Icons.groups_rounded;
  if (has('ห้องสมุด') || has('อ่านหนังสือ')) return Icons.local_library_rounded;
  if (has('สำนักงาน')) return Icons.business_center_rounded;
  if (has('ร้านค้า') || has('โรงอาหาร')) return Icons.storefront_rounded;
  return Icons.meeting_room_rounded;
}

/// จำนวนภาพ 360° ของห้อง (backend ส่งมาใน panorama_count)
int panoramaCount(Map<String, dynamic> room) => int.tryParse('${room['panorama_count']}') ?? 0;

bool hasPanorama(Map<String, dynamic> room) => panoramaCount(room) > 0;

bool hasPin(Map<String, dynamic> room) => room['pin_x'] != null && room['pin_y'] != null;

/// "ห้องบรรยาย · 150 ที่นั่ง" (ข้ามส่วนที่ไม่มีข้อมูล) คืน null ถ้าไม่มีทั้งคู่
String? roomSummary(Map<String, dynamic> room) {
  final type = room['room_type']?.toString().trim();
  final capacity = room['capacity']?.toString().trim();
  final parts = [
    if (type != null && type.isNotEmpty) type,
    if (capacity != null && capacity.isNotEmpty) '$capacity ที่นั่ง',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

Map<String, dynamic> amenitiesOf(Map<String, dynamic> room) {
  final amenities = room['amenities'];
  return amenities is Map ? Map<String, dynamic>.from(amenities) : const {};
}

/// จัดกลุ่มห้องตามชั้น (เรียงชั้นแล้ว)
List<MapEntry<String, List<Map<String, dynamic>>>> groupByFloor(List<Map<String, dynamic>> rooms) {
  final byFloor = <String, List<Map<String, dynamic>>>{};
  for (final room in rooms) {
    byFloor.putIfAbsent(floorOf(room), () => []).add(room);
  }
  return [for (final floor in sortFloors(byFloor.keys)) MapEntry(floor, byFloor[floor]!)];
}
