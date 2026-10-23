import 'package:flutter/material.dart';

import 'app_tabs.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'motion.dart';
import 'open_status.dart';
import 'places_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'tour_screen.dart';

class MainNav extends StatefulWidget {
  const MainNav({super.key});

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;

  // จางเข้าเบา ๆ ตอนสลับแท็บ (ใช้ controller ตัวเดียว ไม่สร้างแท็บใหม่ สถานะในแท็บจึงไม่หาย)
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  // IndexedStack เก็บสถานะของแต่ละแท็บไว้ (เช่น อาคาร/ชั้นที่เลือกในแผนที่) ไม่โหลดใหม่ทุกครั้งที่สลับ
  // แท็บ "เดินชม" ซ่อนไว้ตาม kTourEnabled (ดูเหตุผลใน tour_screen.dart)
  final List<Widget> _screens = [
    const SearchScreen(),
    const MapScreen(),
    if (kTourEnabled) const TourScreen(),
    const PlacesScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // วันปิดพิเศษใช้คำนวณสถานะเปิด/ปิดของห้อง โหลดตอนเปิดแอป และโหลดใหม่ทุกครั้งที่กลับมาใช้แอป
    ClosureStore.refresh();
    WidgetsBinding.instance.addObserver(this);
    AppTabs.request.addListener(_onTabRequest);
  }

  void _onTabRequest() {
    final index = AppTabs.request.value;
    if (index == null) return;
    AppTabs.request.value = null;
    if (index < _screens.length) _onTab(index);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ClosureStore.refresh();
  }

  @override
  void dispose() {
    AppTabs.request.removeListener(_onTabRequest);
    WidgetsBinding.instance.removeObserver(this);
    _fade.dispose();
    super.dispose();
  }

  void _onTab(int index) {
    if (index == _selectedIndex) return;
    Haptics.select();
    setState(() => _selectedIndex = index);
    if (reduceMotion(context)) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0.25);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
          child: IndexedStack(index: _selectedIndex, children: _screens),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onTab,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'ค้นหา',
            ),
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'แผนที่',
            ),
            if (kTourEnabled)
              const NavigationDestination(
                icon: Icon(Icons.threesixty_rounded),
                selectedIcon: Icon(Icons.threesixty_rounded),
                label: 'เดินชม',
              ),
            const NavigationDestination(
              icon: Icon(Icons.apartment_outlined),
              selectedIcon: Icon(Icons.apartment_rounded),
              label: 'อาคาร',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'ตั้งค่า',
            ),
          ],
        ),
      ),
    );
  }
}
