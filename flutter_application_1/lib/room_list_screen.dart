import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_theme.dart';
import 'room_detail_screen.dart';

class RoomListScreen extends StatefulWidget {
  final String buildingName; // รับชื่อตึกมาจากหน้ากดปุ่ม

  const RoomListScreen({super.key, required this.buildingName});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  late final Future<List<dynamic>> _roomsFuture;

  @override
  void initState() {
    super.initState();
    _roomsFuture = fetchRooms();
  }

  // 🌟 ฟังก์ชันสำหรับดึงข้อมูลห้องจาก Backend API
  Future<List<dynamic>> fetchRooms() async {
    final url = ApiConfig.endpoint(
      'api/building/${Uri.encodeComponent(widget.buildingName)}',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('โหลดข้อมูลไม่สำเร็จ');
    }
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required Color tint,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: appCardDecoration(color: tint),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: iconColor,
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.buildingName, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _roomsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return _buildStatusCard(
              icon: Icons.error_outline_rounded,
              iconColor: Colors.redAccent,
              tint: const Color(0xFFFFEDED),
              title: 'เกิดข้อผิดพลาด',
              subtitle: '${snapshot.error}',
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildStatusCard(
              icon: Icons.meeting_room_outlined,
              iconColor: AppColors.primary,
              tint: AppColors.blueTint,
              title: 'ยังไม่มีข้อมูลห้องเรียน',
              subtitle: 'ยังไม่มีห้องเรียนในอาคารนี้ในระบบ',
            );
          }

          final rooms = snapshot.data!;
          final roomsByFloor = <String, List<Map<String, dynamic>>>{};
          for (final rawRoom in rooms) {
            final room = Map<String, dynamic>.from(rawRoom as Map);
            final floor = room['floor']?.toString() ?? '-';
            roomsByFloor.putIfAbsent(floor, () => []).add(room);
          }
          final floors = roomsByFloor.keys.toList()
            ..sort((first, second) {
              final firstNumber = int.tryParse(first);
              final secondNumber = int.tryParse(second);
              if (firstNumber != null && secondNumber != null) {
                return firstNumber.compareTo(secondNumber);
              }
              if (firstNumber != null) return -1;
              if (secondNumber != null) return 1;
              return first.compareTo(second);
            });
          final items = <Object>[];
          for (final floor in floors) {
            items.add(floor);
            items.addAll(roomsByFloor[floor]!);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'ชั้น $item',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final room = item as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: appCardDecoration(),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.blueTint,
                      child: Icon(Icons.meeting_room_rounded, color: AppColors.primary),
                    ),
                    title: Text(
                      'รหัสห้อง: ${room['room_code']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: AppColors.ink,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoomDetailScreen(room: room),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
