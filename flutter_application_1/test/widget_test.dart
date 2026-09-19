import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/app_theme.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the main navigation and switches tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    for (final label in ['ค้นหา', 'แผนที่', 'อาคาร', 'บันทึก', 'ตั้งค่า']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('ตั้งค่า').last);
    await tester.pump();
    expect(find.text('ล้างห้องโปรด'), findsOneWidget);
    expect(find.text('ที่อยู่เซิร์ฟเวอร์'), findsNothing);

    // แตะ "เวอร์ชัน" 5 ครั้งติดกันเพื่อเปิดการตั้งค่าเซิร์ฟเวอร์ที่ซ่อนไว้
    await tester.ensureVisible(find.text('เวอร์ชัน'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('เวอร์ชัน'));
    }
    await tester.pumpAndSettle();
    expect(find.text('ที่อยู่เซิร์ฟเวอร์'), findsOneWidget);
    await tester.tap(find.text('บันทึก').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('บันทึก').last);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีห้องที่บันทึกไว้'), findsOneWidget);
  });

  testWidgets('switches to dark mode from settings and back', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('ตั้งค่า').last);
    await tester.pumpAndSettle();
    expect(AppColors.dark, isFalse);

    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();
    expect(AppColors.dark, isTrue);
    expect(ThemeController.mode.value, ThemeMode.dark);

    await tester.tap(find.text('สว่าง'));
    await tester.pumpAndSettle();
    expect(AppColors.dark, isFalse);
  });
}
