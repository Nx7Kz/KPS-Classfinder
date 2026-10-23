import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/open_status.dart';

/// เวลาไทย = UTC+7 จึงแปลงเวลาไทยเป็น UTC ก่อนส่งเข้าฟังก์ชัน (ผลต้องไม่ขึ้นกับเขตเวลาเครื่องที่รันเทสต์)
DateTime bangkok(String isoLocal) => DateTime.parse('$isoLocal+07:00');

const weekdays = {
  'mon': {'open': '08:00', 'close': '16:00'},
  'tue': {'open': '08:00', 'close': '16:00'},
  'wed': null,
  'thu': null,
  'fri': null,
  'sat': null,
  'sun': null,
};

void main() {
  // 2026-10-26 เป็นวันจันทร์
  group('computeOpenStatus', () {
    test('เปิดอยู่ในเวลาทำการ', () {
      final status = computeOpenStatus(hours: weekdays, at: bangkok('2026-10-26T10:00:00'));
      expect(status.state, OpenState.open);
      expect(status.label, 'เปิดอยู่ · ปิด 16:00 น.');
      expect(status.shortLabel, 'เปิดอยู่');
    });

    test('เวลาปิดเป็นขอบเขตเปิดปลายเปิด (16:00 ปิดแล้ว)', () {
      final status = computeOpenStatus(hours: weekdays, at: bangkok('2026-10-26T16:00:00'));
      expect(status.state, OpenState.closed);
      expect(status.label, 'ปิดอยู่ · เปิดพรุ่งนี้ 08:00 น.');
    });

    test('ก่อนเปิดวันนี้', () {
      final status = computeOpenStatus(hours: weekdays, at: bangkok('2026-10-26T06:30:00'));
      expect(status.label, 'ปิดอยู่ · เปิดวันนี้ 08:00 น.');
    });

    test('ข้ามวันที่ปิดไปวันเปิดถัดไป', () {
      final status = computeOpenStatus(hours: weekdays, at: bangkok('2026-10-27T17:00:00'));
      expect(status.label, 'ปิดอยู่ · เปิดวันจันทร์ 08:00 น.');
    });

    test('คิดตามเวลาไทยแม้ส่งเวลา UTC เข้ามา (UTC 02:00 = ไทย 09:00)', () {
      final status = computeOpenStatus(hours: weekdays, at: DateTime.utc(2026, 10, 26, 2));
      expect(status.state, OpenState.open);
    });

    test('ข้ามเที่ยงคืนตามเวลาไทย (UTC 18:00 วันอาทิตย์ = ไทย 01:00 วันจันทร์)', () {
      final status = computeOpenStatus(hours: weekdays, at: DateTime.utc(2026, 10, 25, 18));
      expect(status.label, 'ปิดอยู่ · เปิดวันนี้ 08:00 น.');
    });

    test('ไม่มีเวลาทำการ = ไม่ระบุ', () {
      final status = computeOpenStatus(hours: null, at: bangkok('2026-10-26T10:00:00'));
      expect(status.state, OpenState.unknown);
      expect(status.isKnown, false);
    });

    test('ปิดปรับปรุงเด่นกว่าเวลาทำการ', () {
      final status = computeOpenStatus(status: 'maintenance', hours: weekdays, at: bangkok('2026-10-26T10:00:00'));
      expect(status.state, OpenState.closed);
      expect(status.label, 'ปิดปรับปรุง');
    });
  });

  group('closures', () {
    tearDown(() => ClosureStore.setForTest(const []));

    test('วันปิดทั้งมหาวิทยาลัยทับเวลาปกติ', () {
      ClosureStore.setForTest([
        {'building_id': null, 'room_id': null, 'start_date': '2026-10-26', 'end_date': '2026-10-26', 'reason': 'วันหยุดชดเชย'},
      ]);
      final status = computeOpenStatus(hours: weekdays, at: bangkok('2026-10-26T10:00:00'));
      expect(status.isClosure, true);
      expect(status.detail, 'วันหยุดชดเชย');
    });

    test('ตอนปิดวันนี้ วันเปิดถัดไปข้ามวันที่ปิด', () {
      ClosureStore.setForTest([
        {'building_id': null, 'room_id': null, 'start_date': '2026-10-27', 'end_date': '2026-10-27', 'reason': null},
      ]);
      final status = computeOpenStatus(hours: weekdays, at: bangkok('2026-10-26T17:00:00'));
      expect(status.label, 'ปิดอยู่ · เปิดวันจันทร์ 08:00 น.');
    });

    test('วันปิดของอาคารอื่นไม่กระทบ', () {
      ClosureStore.setForTest([
        {'building_id': 9, 'room_id': null, 'start_date': '2026-10-26', 'end_date': '2026-10-26', 'reason': null},
      ]);
      final status = computeOpenStatus(hours: weekdays, buildingId: 3, at: bangkok('2026-10-26T10:00:00'));
      expect(status.state, OpenState.open);
    });

    test('วันปิดเฉพาะห้องกระทบเฉพาะห้องนั้น', () {
      ClosureStore.setForTest([
        {'building_id': 3, 'room_id': 5, 'start_date': '2026-10-26', 'end_date': '2026-10-28', 'reason': 'ซ่อมแอร์'},
      ]);
      final closed = computeOpenStatus(hours: weekdays, roomId: 5, buildingId: 3, at: bangkok('2026-10-26T10:00:00'));
      final other = computeOpenStatus(hours: weekdays, roomId: 6, buildingId: 3, at: bangkok('2026-10-26T10:00:00'));
      expect(closed.isClosure, true);
      expect(other.state, OpenState.open);
    });
  });

  group('room helpers', () {
    test('ห้องใช้เวลาของอาคารเมื่อไม่ได้กำหนดเอง และของห้องเด่นกว่า', () {
      final inherit = {'open_hours': null, 'building_open_hours': weekdays, 'status': 'active', 'id': 1, 'building_id': 3};
      expect(effectiveHours(inherit), isNotNull);
      final own = {
        'open_hours': {'mon': {'open': '09:00', 'close': '10:00'}},
        'building_open_hours': weekdays,
      };
      expect(effectiveHours(own)!['mon']['open'], '09:00');
      expect(roomOpenStatus(inherit, at: bangkok('2026-10-26T10:00:00')).state, OpenState.open);
    });

    test('ตารางรายสัปดาห์เรียงจันทร์ถึงอาทิตย์และมีแถววันนี้แถวเดียว', () {
      final rows = weeklyHoursRows(weekdays, at: bangkok('2026-10-27T10:00:00'));
      expect(rows.map((r) => r.day).toList(), ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์']);
      expect(rows.where((r) => r.isToday).single.day, 'อังคาร');
      expect(rows[0].text, '08:00 – 16:00 น.');
      expect(rows[2].isClosed, true);
    });
  });
}
