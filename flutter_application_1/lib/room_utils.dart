/// ฟังก์ชันช่วยจัดการข้อมูลห้อง/ชั้นที่ใช้ร่วมกันหลายหน้า
library;

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
