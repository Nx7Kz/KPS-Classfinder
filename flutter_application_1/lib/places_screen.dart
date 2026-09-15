import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'room_list_screen.dart';

class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  static const _buildings = [
    (
      name: 'อาคารเรียนรวม 3 (ศร.3)',
      subtitle: 'ห้องเรียนรวม ชั้น 2-3',
      icon: Icons.domain_rounded,
      color: AppColors.primary,
      tint: AppColors.blueTint,
    ),
    (
      name: 'อาคารเรียน 80 ปี',
      subtitle: 'ห้องเรียนคณะและห้องปฏิบัติการ',
      icon: Icons.apartment_rounded,
      color: AppColors.accent,
      tint: AppColors.goldTint,
    ),
  ];

  Widget _buildBuildingCard(
    BuildContext context, {
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color tint,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoomListScreen(buildingName: name),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: appCardDecoration(),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: tint,
              radius: 28,
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.muted, size: 16),
          ],
        ),
      ),
    );
  }

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
                'เลือกอาคารเรียน',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'เลือกอาคารเพื่อดูรายการห้องเรียนทั้งหมด',
                style: TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 24),
              for (final building in _buildings) ...[
                _buildBuildingCard(
                  context,
                  name: building.name,
                  subtitle: building.subtitle,
                  icon: building.icon,
                  color: building.color,
                  tint: building.tint,
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
