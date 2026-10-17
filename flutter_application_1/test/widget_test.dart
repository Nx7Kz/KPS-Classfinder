import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/app_theme.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/motion.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the main navigation and switches tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    for (final label in ['ค้นหา', 'แผนที่', 'เดินชม', 'อาคาร', 'ตั้งค่า']) {
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
    await tester.tapAt(const Offset(8, 8)); // แตะนอกกล่องเพื่อปิด
    await tester.pumpAndSettle();
    expect(find.text('ที่อยู่เซิร์ฟเวอร์'), findsNothing);

    await tester.tap(find.text('เดินชม').last);
    await tester.pumpAndSettle();
    expect(find.text('เดินชมอาคาร'), findsOneWidget);
  });

  testWidgets('search page shows favorite rooms and opens the saved list', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'favorite_rooms': jsonEncode([
        {'id': 12, 'room_code': 'LH3-201', 'building_name': 'อาคารทดสอบ', 'floor': '2'},
      ]),
    });
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('ห้องโปรด'), findsOneWidget);
    expect(find.text('LH3-201'), findsOneWidget);

    await tester.tap(find.text('ดูทั้งหมด'));
    await tester.pumpAndSettle();
    expect(find.text('ที่บันทึกไว้'), findsOneWidget);
    expect(find.text('ห้องโปรด (1)'), findsOneWidget);
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

  testWidgets('list items fade in, and stay still when reduce motion is on', (WidgetTester tester) async {
    Future<double> opacityAfter(Duration elapsed, {required bool reduce}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: FadeSlideIn(index: 2, child: Text('room')),
          ),
        ),
      );
      await tester.pump(elapsed);
      final opacity = tester.widgetList<Opacity>(find.ancestor(of: find.text('room'), matching: find.byType(Opacity)));
      return opacity.isEmpty ? 1.0 : opacity.first.opacity;
    }

    expect(await opacityAfter(const Duration(milliseconds: 60), reduce: false), lessThan(1.0));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('room'), matching: find.byType(Opacity))).opacity, 1.0);

    await tester.pumpWidget(const SizedBox());
    expect(await opacityAfter(Duration.zero, reduce: true), 1.0);
  });
}
