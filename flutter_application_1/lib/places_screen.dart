import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_theme.dart';
import 'room_list_screen.dart';

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  late Future<List<Map<String, dynamic>>> _buildingsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _buildingsFuture = _fetchBuildings();
  }

  Future<List<Map<String, dynamic>>> _fetchBuildings() async {
    final url = ApiConfig.endpoint('api/buildings');
    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('โหลดข้อมูลอาคารไม่สำเร็จ');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('รูปแบบข้อมูลอาคารไม่ถูกต้อง');
    }
    return decoded.map((b) => Map<String, dynamic>.from(b as Map)).toList();
  }

  Future<void> _refresh() async {
    final future = _fetchBuildings();
    setState(() => _buildingsFuture = future);
    await future;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
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
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line),
                  boxShadow: const [
                    BoxShadow(color: Color(0x120F172A), blurRadius: 16, offset: Offset(0, 6)),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  style: const TextStyle(color: AppColors.ink),
                  decoration: const InputDecoration(
                    hintText: 'ค้นหาชื่อตึก รหัสอาคาร เช่น LH3',
                    hintStyle: TextStyle(color: AppColors.muted, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _buildingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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

        final buildings = snapshot.data ?? const [];
        final visible = buildings.where((b) {
          if (_query.isEmpty) return true;
          final name = (b['name']?.toString() ?? '').toLowerCase();
          final code = (b['code']?.toString() ?? '').toLowerCase();
          return name.contains(_query) || code.contains(_query);
        }).toList();

        if (buildings.isEmpty) {
          return _buildStatusCard(
            icon: Icons.domain_outlined,
            iconColor: AppColors.primary,
            tint: AppColors.blueTint,
            title: 'ยังไม่มีอาคารในระบบ',
            subtitle: 'รอแอดมินเพิ่มข้อมูลอาคาร',
          );
        }

        if (visible.isEmpty) {
          return _buildStatusCard(
            icon: Icons.search_off_rounded,
            iconColor: AppColors.muted,
            tint: AppColors.blueTint,
            title: 'ไม่พบอาคารที่ค้นหา',
            subtitle: 'ลองค้นหาด้วยชื่ออื่นหรือรหัสอาคาร',
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) => _buildBuildingCard(context, visible[index]),
          ),
        );
      },
    );
  }

  Widget _buildBuildingCard(BuildContext context, Map<String, dynamic> building) {
    final code = building['code']?.toString() ?? '-';
    final name = building['name']?.toString() ?? '-';
    final description = building['description']?.toString();
    final location = building['location']?.toString();
    final floorCount = building['floor_count']?.toString() ?? '0';
    final roomCount = building['room_count']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: appCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.blueTint,
              borderRadius: BorderRadius.circular(6),
              border: const Border(left: BorderSide(color: AppColors.primary, width: 3)),
            ),
            child: Text(
              '[ $code ]',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                fontFamily: 'monospace',
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(location, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _buildStatChip(Icons.layers_outlined, '$floorCount ชั้น'),
              const SizedBox(width: 10),
              _buildStatChip(Icons.meeting_room_outlined, '$roomCount ห้อง'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RoomListScreen(buildingName: name)),
                );
              },
              child: const Text('เลือกอาคารนี้'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required Color tint,
    required String title,
    required String subtitle,
  }) {
    return Center(
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
              style: const TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w700),
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
    );
  }
}
