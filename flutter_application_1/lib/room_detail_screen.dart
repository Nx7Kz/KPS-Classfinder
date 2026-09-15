import 'package:flutter/material.dart';

import 'app_theme.dart';
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
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: appCardDecoration(color: AppColors.goldTint),
                child: const Row(
                  children: [
                    Icon(Icons.map_outlined, color: AppColors.accent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'แผนที่นำทางไปยังห้องนี้กำลังจัดเตรียม เร็ว ๆ นี้',
                        style: TextStyle(color: AppColors.ink, height: 1.4),
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
