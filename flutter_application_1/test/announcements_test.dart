import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/announcements.dart';
import 'package:flutter_application_1/open_status.dart';

DateTime bangkok(String isoLocal) => DateTime.parse('$isoLocal+07:00');

Map<String, dynamic> closure(int id, String start, String end, {String? reason, int? buildingId, String? buildingName, String? roomCode}) => {
      'id': id,
      'building_id': buildingId,
      'room_id': roomCode == null ? null : id,
      'start_date': start,
      'end_date': end,
      'reason': reason,
      'building_name': buildingName,
      'room_code': roomCode,
    };

void main() {
  tearDown(() => ClosureStore.setForTest(const []));

  final buildings = [
    {'id': 3, 'name': 'อาคาร A', 'maintenance_count': 2},
    {'id': 4, 'name': 'อาคาร B', 'maintenance_count': 0},
  ];

  test('วันปิดที่เกิดขึ้นวันนี้เป็นเร่งด่วนและขึ้นก่อน วันปิดที่เลยไปแล้วหรือไกลเกิน 14 วันไม่ขึ้น', () {
    ClosureStore.setForTest([
      closure(1, '2026-10-30', '2026-10-30', reason: 'สอบ', buildingId: 3, buildingName: 'อาคาร A'),
      closure(2, '2026-10-26', '2026-10-27', reason: 'วันหยุดชดเชย'),
      closure(3, '2026-10-20', '2026-10-21'),
      closure(4, '2026-12-01', '2026-12-02'),
    ]);
    final items = buildAnnouncements(buildings, at: bangkok('2026-10-26T10:00:00'));

    expect(items.map((i) => i.id).toList(), ['closure-2', 'closure-1', 'maintenance-3']);
    expect(items[0].urgent, true);
    expect(items[0].title, 'ปิดทำการวันนี้ • ทั้งมหาวิทยาลัย');
    expect(items[0].detail, 'ถึง 27 ต.ค. • วันหยุดชดเชย');
    expect(items[1].urgent, false);
    expect(items[1].title, 'ปิดทำการ 30 ต.ค. • อาคาร A');
    expect(items[1].building!['id'], 3);
    expect(items[2].title, 'ปิดปรับปรุง 2 ห้อง • อาคาร A');
  });

  test('วันปิดเฉพาะห้องแสดงชื่อห้องพร้อมอาคาร และไม่มีประกาศเมื่อไม่มีข้อมูล', () {
    ClosureStore.setForTest([closure(5, '2026-10-27', '2026-10-28', buildingId: 3, buildingName: 'อาคาร A', roomCode: 'LH3-201')]);
    final items = buildAnnouncements(buildings, at: bangkok('2026-10-26T10:00:00'));
    expect(items.first.title, 'ปิดทำการ 27 ต.ค. – 28 ต.ค. • ห้อง LH3-201 (อาคาร A)');

    ClosureStore.setForTest(const []);
    expect(buildAnnouncements([buildings[1]], at: bangkok('2026-10-26T10:00:00')), isEmpty);
  });

  test('shortThaiDate', () {
    expect(shortThaiDate('2026-01-05'), '5 ม.ค.');
    expect(shortThaiDate('2026-12-31'), '31 ธ.ค.');
    expect(shortThaiDate('bad'), 'bad');
  });
}
