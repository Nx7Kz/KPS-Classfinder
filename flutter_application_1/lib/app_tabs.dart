import 'package:flutter/foundation.dart';

import 'tour_screen.dart' show kTourEnabled;

/// ให้หน้าอื่นสั่งสลับแท็บล่างได้ (เช่น ปุ่มลัด "ดูทั้งหมด" / "เปิดแผนที่" บนหน้าค้นหา)
/// ลำดับแท็บต้องตรงกับ MainNav: ค้นหา, แผนที่, (เดินชม ถ้าเปิดใช้), อาคาร, ตั้งค่า
class AppTabs {
  const AppTabs._();

  static const search = 0;
  static const map = 1;
  static int get places => kTourEnabled ? 3 : 2;

  /// MainNav ฟังค่านี้ แล้วเคลียร์กลับเป็น null หลังสลับแท็บ
  static final ValueNotifier<int?> request = ValueNotifier<int?>(null);

  static void go(int index) => request.value = index;
}
