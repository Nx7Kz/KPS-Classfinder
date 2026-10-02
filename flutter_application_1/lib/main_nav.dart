import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'map_screen.dart';
import 'motion.dart';
import 'places_screen.dart';
import 'saved_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class MainNav extends StatefulWidget {
  const MainNav({super.key});

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  // จางเข้าเบา ๆ ตอนสลับแท็บ (ใช้ controller ตัวเดียว ไม่สร้างแท็บใหม่ สถานะในแท็บจึงไม่หาย)
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  // IndexedStack เก็บสถานะของแต่ละแท็บไว้ (เช่น อาคาร/ชั้นที่เลือกในแผนที่) ไม่โหลดใหม่ทุกครั้งที่สลับ
  final List<Widget> _screens = const [
    SearchScreen(),
    MapScreen(),
    PlacesScreen(),
    SavedScreen(),
    SettingsScreen(),
  ];

  @override
  void dispose() {
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'ค้นหา',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'แผนที่',
            ),
            NavigationDestination(
              icon: Icon(Icons.apartment_outlined),
              selectedIcon: Icon(Icons.apartment_rounded),
              label: 'อาคาร',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border_rounded),
              selectedIcon: Icon(Icons.bookmark_rounded),
              label: 'บันทึก',
            ),
            NavigationDestination(
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
