/// เวลาทำการ: คำนวณสถานะ "เปิดอยู่/ปิดอยู่" ในแอปเอง (เวลาไทย) จากเวลาทำการที่มากับข้อมูลห้อง/อาคาร + วันปิดพิเศษ
/// คำนวณฝั่งแอปเพราะรายการโปรด/ประวัติเก็บข้อมูลห้องไว้ในเครื่อง ถ้าใช้ป้ายสถานะจากเซิร์ฟเวอร์จะค้างเก่า
library;

import 'package:flutter/foundation.dart';

import 'api_client.dart';

const _weekKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
const _weekLabels = ['วันอาทิตย์', 'วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์'];

/// ลำดับแสดงในตารางเวลา: จันทร์ → อาทิตย์
const _displayOrder = [1, 2, 3, 4, 5, 6, 0];

enum OpenState { open, closed, unknown }

class OpenStatus {
  final OpenState state;

  /// ข้อความเต็ม เช่น "เปิดอยู่ · ปิด 16:00 น." / "ปิดอยู่ · เปิดพรุ่งนี้ 08:00 น."
  final String label;

  /// ข้อความสั้นสำหรับป้ายเล็ก ๆ: "เปิดอยู่" / "ปิดอยู่" / "ปิดทำการ"
  final String shortLabel;

  /// เหตุผลวันปิดพิเศษ (ถ้ามี)
  final String? detail;
  final bool isClosure;

  const OpenStatus(this.state, this.label, this.shortLabel, {this.detail, this.isClosure = false});

  bool get isKnown => state != OpenState.unknown;
}

/// วันปิดพิเศษที่ผู้ดูแลตั้งไว้ (ทั้งมหาวิทยาลัย/อาคาร/ห้อง) โหลดครั้งเดียวตอนเปิดแอปแล้วใช้ร่วมกันทุกหน้า
class ClosureStore {
  ClosureStore._();

  static List<Map<String, dynamic>> _items = const [];

  /// เพิ่มค่าเมื่อโหลดวันปิดใหม่ ให้หน้าที่แสดงสถานะรีเฟรชตัวเองได้
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<Map<String, dynamic>> get items => _items;

  @visibleForTesting
  static void setForTest(List<Map<String, dynamic>> items) => _items = items;

  /// เชื่อมต่อไม่ได้ก็ใช้ค่าเดิมต่อ (ไม่ถือเป็นข้อผิดพลาด สถานะจะอิงเวลาทำการปกติ)
  static Future<void> refresh() async {
    try {
      _items = await Api.closures();
      revision.value++;
    } catch (_) {}
  }
}

Map<String, dynamic>? _asHours(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;

/// เวลาทำการที่ห้องใช้จริง: ของห้องเอง ถ้าไม่ได้กำหนดใช้ของอาคาร (null = ไม่ระบุ)
Map<String, dynamic>? effectiveHours(Map<String, dynamic> room) =>
    _asHours(room['open_hours']) ?? _asHours(room['building_open_hours']);

/// เวลาไทย (UTC+7) แต่เก็บเป็น DateTime แบบ UTC เพื่อใช้ฟิลด์ปี/เดือน/วัน/ชั่วโมงตรง ๆ ไม่ขึ้นกับเขตเวลาเครื่อง
DateTime _bangkok(DateTime? at) => (at ?? DateTime.now()).toUtc().add(const Duration(hours: 7));

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int _minutes(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

int? _id(dynamic value) => value == null ? null : int.tryParse(value.toString());

/// วันปิดที่ตรงวันนั้น ระดับห้องเด่นกว่าอาคาร และอาคารเด่นกว่าทั้งมหาวิทยาลัย
Map<String, dynamic>? _findClosure(String date, int? roomId, int? buildingId) {
  Map<String, dynamic>? best;
  var bestRank = 0;
  for (final closure in ClosureStore.items) {
    final start = closure['start_date']?.toString() ?? '';
    final end = closure['end_date']?.toString() ?? '';
    if (date.compareTo(start) < 0 || date.compareTo(end) > 0) continue;
    final closureRoom = _id(closure['room_id']);
    final closureBuilding = _id(closure['building_id']);
    var rank = 1;
    if (closureRoom != null) {
      rank = closureRoom == roomId ? 3 : 0;
    } else if (closureBuilding != null) {
      rank = closureBuilding == buildingId ? 2 : 0;
    }
    if (rank > bestRank) {
      best = closure;
      bestRank = rank;
    }
  }
  return best;
}

Map<String, dynamic>? _slot(Map<String, dynamic> hours, int weekdayIndex) {
  final value = hours[_weekKeys[weekdayIndex]];
  if (value is! Map) return null;
  final open = value['open']?.toString();
  final close = value['close']?.toString();
  if (open == null || close == null || open.length < 5 || close.length < 5) return null;
  return {'open': open, 'close': close};
}

OpenStatus computeOpenStatus({
  String? status,
  Map<String, dynamic>? hours,
  int? roomId,
  int? buildingId,
  DateTime? at,
}) {
  if (status == 'maintenance') return const OpenStatus(OpenState.closed, 'ปิดปรับปรุง', 'ปิดปรับปรุง');

  final now = _bangkok(at);
  final today = _dateKey(now);
  final closure = _findClosure(today, roomId, buildingId);
  if (closure != null) {
    final reason = closure['reason']?.toString();
    return OpenStatus(
      OpenState.closed,
      'ปิดทำการ',
      'ปิดทำการ',
      detail: reason == null || reason.isEmpty ? null : reason,
      isClosure: true,
    );
  }
  if (hours == null) return const OpenStatus(OpenState.unknown, 'ไม่ระบุเวลาทำการ', '');

  final nowMinutes = now.hour * 60 + now.minute;
  final todaySlot = _slot(hours, now.weekday % 7);
  if (todaySlot != null && nowMinutes >= _minutes(todaySlot['open']) && nowMinutes < _minutes(todaySlot['close'])) {
    return OpenStatus(OpenState.open, 'เปิดอยู่ · ปิด ${todaySlot['close']} น.', 'เปิดอยู่');
  }

  for (var offset = 0; offset <= 7; offset++) {
    final target = now.add(Duration(days: offset));
    final slot = _slot(hours, target.weekday % 7);
    if (slot == null) continue;
    if (offset == 0 && nowMinutes >= _minutes(slot['open'])) continue; // เลยเวลาปิดของวันนี้ไปแล้ว
    if (offset > 0 && _findClosure(_dateKey(target), roomId, buildingId) != null) continue;
    final when = offset == 0 ? 'วันนี้' : (offset == 1 ? 'พรุ่งนี้' : _weekLabels[target.weekday % 7]);
    return OpenStatus(OpenState.closed, 'ปิดอยู่ · เปิด$when ${slot['open']} น.', 'ปิดอยู่');
  }
  return const OpenStatus(OpenState.closed, 'ปิดทำการ', 'ปิดอยู่');
}

OpenStatus roomOpenStatus(Map<String, dynamic> room, {DateTime? at}) => computeOpenStatus(
      status: room['status']?.toString(),
      hours: effectiveHours(room),
      roomId: _id(room['id']),
      buildingId: _id(room['building_id']),
      at: at,
    );

OpenStatus buildingOpenStatus(Map<String, dynamic> building, {DateTime? at}) => computeOpenStatus(
      hours: _asHours(building['open_hours']),
      buildingId: _id(building['id']),
      at: at,
    );

/// สรุปเวลาทำการสั้น ๆ เช่น "จ.–ศ. 08:00–16:30 • ส.–อา. ปิด" (วันติดกันที่เวลาเหมือนกันรวมเป็นช่วงเดียว)
String summarizeHours(Map<String, dynamic> hours) {
  const shortDays = {1: 'จ.', 2: 'อ.', 3: 'พ.', 4: 'พฤ.', 5: 'ศ.', 6: 'ส.', 0: 'อา.'};
  final groups = <({String signature, String start, String end})>[];
  for (final index in _displayOrder) {
    final slot = _slot(hours, index);
    final signature = slot == null ? 'ปิด' : '${slot['open']}–${slot['close']}';
    final day = shortDays[index]!;
    if (groups.isNotEmpty && groups.last.signature == signature) {
      groups[groups.length - 1] = (signature: signature, start: groups.last.start, end: day);
    } else {
      groups.add((signature: signature, start: day, end: day));
    }
  }
  return groups
      .map((g) => '${g.start == g.end ? g.start : '${g.start}–${g.end}'} ${g.signature}')
      .join(' • ');
}

/// หนึ่งแถวของตารางเวลาทำการรายสัปดาห์
class HoursRow {
  final String day;

  /// "08:00 – 16:30 น." หรือ "ปิด"
  final String text;
  final bool isToday;
  final bool isClosed;

  const HoursRow(this.day, this.text, this.isToday, this.isClosed);
}

List<HoursRow> weeklyHoursRows(Map<String, dynamic> hours, {DateTime? at}) {
  final todayIndex = _bangkok(at).weekday % 7;
  return [
    for (final index in _displayOrder)
      () {
        final slot = _slot(hours, index);
        return HoursRow(
          _weekLabels[index].replaceFirst('วัน', ''),
          slot == null ? 'ปิด' : '${slot['open']} – ${slot['close']} น.',
          index == todayIndex,
          slot == null,
        );
      }(),
  ];
}
