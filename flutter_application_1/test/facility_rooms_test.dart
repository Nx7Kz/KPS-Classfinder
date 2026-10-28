import 'package:flutter_application_1/room_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ห้องน้ำ ลิฟต์ บันได โถง ร้านค้า นับเป็นสิ่งอำนวยความสะดวก', () {
    for (final type in ['ห้องน้ำ', 'ลิฟต์', 'บันได', 'ห้องโถง', 'ร้านค้า / โรงอาหาร', 'ห้องสำนักงาน', 'ห้องสมุด / ห้องอ่านหนังสือ']) {
      expect(isFacilityRoom({'room_type': type, 'room_code': 'X-1'}), isTrue, reason: type);
    }
  });

  test('ห้องบรรยาย Lab ห้องประชุม และห้องที่ไม่ระบุประเภทนับเป็นห้องเรียน', () {
    for (final type in ['ห้องบรรยาย', 'ห้องปฏิบัติการ (Lab)', 'ห้องคอมพิวเตอร์', 'ห้องประชุม', 'ห้องสัมมนา', null, '']) {
      expect(isFacilityRoom({'room_type': type, 'room_code': 'KH80-201'}), isFalse, reason: '$type');
    }
  });

  test('classroomCountOf ใช้ค่าจากเซิร์ฟเวอร์ และถอยกลับไปใช้ room_count เมื่อเป็นเซิร์ฟเวอร์รุ่นเก่า', () {
    expect(classroomCountOf({'room_count': 13, 'classroom_count': 8}), 8);
    expect(classroomCountOf({'room_count': 13}), 13);
  });
}
