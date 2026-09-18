import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'map_screen.dart';
import 'room_store.dart';

class RoomDetailScreen extends StatefulWidget {
  final Map<String, dynamic> room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  bool _isFavorite = false;
  bool _isLoadingFavorite = true;

  @override
  void initState() {
    super.initState();
    RoomStore.addRecent(widget.room);
    _loadFavoriteState();
  }

  Future<void> _loadFavoriteState() async {
    final isFavorite = await RoomStore.isFavorite(widget.room);
    if (!mounted) return;
    setState(() {
      _isFavorite = isFavorite;
      _isLoadingFavorite = false;
    });
  }

  Future<void> _toggleFavorite() async {
    final nowFavorite = await RoomStore.toggleFavorite(widget.room);
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowFavorite ? 'เพิ่มในรายการโปรดแล้ว' : 'นำออกจากรายการโปรดแล้ว'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildAmenityChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.blueTint,
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final roomCode = room['room_code']?.toString() ?? '-';
    final buildingName = room['building_name']?.toString() ?? '-';
    final floor = room['floor']?.toString() ?? '-';
    final roomType = room['room_type']?.toString();
    final capacity = room['capacity']?.toString();
    final isMaintenance = room['status']?.toString() == 'maintenance';
    final amenities = room['amenities'];
    final amenitiesMap = amenities is Map ? Map<String, dynamic>.from(amenities) : const <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดห้อง', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: _isFavorite ? 'นำออกจากรายการโปรด' : 'เพิ่มในรายการโปรด',
            onPressed: _isLoadingFavorite ? null : _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _isFavorite ? AppColors.accent : AppColors.muted,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: appCardDecoration(color: AppColors.blueTint),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.meeting_room_rounded, color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      roomCode,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      buildingName,
                      style: const TextStyle(color: AppColors.muted, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: appCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.domain_rounded, 'อาคาร', buildingName),
                    const SizedBox(height: 18),
                    _buildInfoRow(Icons.layers_rounded, 'ชั้น', floor),
                    const SizedBox(height: 18),
                    _buildInfoRow(Icons.tag_rounded, 'รหัสห้อง', roomCode),
                    if (roomType != null && roomType.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildInfoRow(Icons.category_rounded, 'ประเภทห้อง', roomType),
                    ],
                    if (capacity != null && capacity.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildInfoRow(Icons.event_seat_rounded, 'ความจุ', '$capacity ที่นั่ง'),
                    ],
                  ],
                ),
              ),
              if (isMaintenance) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: appCardDecoration(color: const Color(0xFFFFF4E5)),
                  child: const Row(
                    children: [
                      Icon(Icons.build_rounded, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'ห้องนี้กำลังปิดปรับปรุง อาจไม่สามารถใช้งานได้ในขณะนี้',
                          style: TextStyle(color: AppColors.ink, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (amenitiesMap.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: appCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'สิ่งอำนวยความสะดวก',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (amenitiesMap['seats'] != null)
                            _buildAmenityChip(Icons.event_seat_rounded, '${amenitiesMap['seats']} ที่นั่ง'),
                          if (amenitiesMap['outlets'] != null)
                            _buildAmenityChip(Icons.power_rounded, '${amenitiesMap['outlets']} จุดปลั๊กไฟ'),
                          if (amenitiesMap['ac'] != null)
                            _buildAmenityChip(Icons.ac_unit_rounded, '${amenitiesMap['ac']} เครื่องปรับอากาศ'),
                          if (amenitiesMap['wifi'] != null)
                            _buildAmenityChip(Icons.wifi_rounded, '${amenitiesMap['wifi']}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: appCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.map_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'ผังนำทางห้อง',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.blueTint,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ชั้น $floor',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MapScreen(
                                initialBuilding: buildingName,
                                initialFloor: floor,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.location_on_rounded, size: 18),
                        label: const Text('เปิดแผนที่แสดงตำแหน่งห้อง'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
