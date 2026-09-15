import 'package:flutter/material.dart';

import 'app_theme.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'แผนที่มหาวิทยาลัย',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ค้นหาอาคารและห้องเรียนได้ในที่เดียว',
                style: TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: appCardDecoration(color: AppColors.blueTint),
                child: const Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.map_outlined, color: Colors.white, size: 38),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'แผนที่กำลังจัดเตรียม',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'ระหว่างนี้สามารถค้นหาห้องหรือเลือกอาคารจากเมนูด้านล่างได้',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
