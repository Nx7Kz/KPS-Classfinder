import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'room_list_screen.dart';
import 'skeleton.dart';
import 'widgets.dart';

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
    _buildingsFuture = Api.buildings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = Api.buildings();
    setState(() => _buildingsFuture = future);
    try {
      await future;
    } catch (_) {
      // ข้อผิดพลาดแสดงในหน้าจออยู่แล้ว
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: 'อาคารเรียน', subtitle: 'เลือกอาคารเพื่อดูห้องเรียนทั้งหมด'),
          const SizedBox(height: 16),
          AppSearchField(
            controller: _searchController,
            hint: 'ค้นหาชื่ออาคาร หรือรหัส เช่น LH3',
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _buildingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SkeletonList(count: 3, spacing: 12, itemBuilder: (_) => const BuildingCardSkeleton());
        }

        if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _refresh);

        final buildings = snapshot.data ?? const [];
        if (buildings.isEmpty) {
          return const StateView(
            icon: Icons.apartment_outlined,
            title: 'ยังไม่มีอาคารในระบบ',
            message: 'รอผู้ดูแลเพิ่มข้อมูลอาคาร',
          );
        }

        final visible = buildings.where((b) {
          if (_query.isEmpty) return true;
          final name = (b['name']?.toString() ?? '').toLowerCase();
          final code = (b['code']?.toString() ?? '').toLowerCase();
          return name.contains(_query) || code.contains(_query);
        }).toList();

        if (visible.isEmpty) {
          return const StateView(
            icon: Icons.search_off_rounded,
            title: 'ไม่พบอาคารที่ค้นหา',
            message: 'ลองค้นหาด้วยชื่ออื่นหรือรหัสอาคาร',
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _BuildingCard(building: visible[index], query: _query),
          ),
        );
      },
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final Map<String, dynamic> building;
  final String query;

  const _BuildingCard({required this.building, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final code = building['code']?.toString() ?? '-';
    final name = building['name']?.toString() ?? '-';
    final description = building['description']?.toString();
    final location = building['location']?.toString();
    final floorCount = building['floor_count']?.toString() ?? '0';
    final roomCount = building['room_count']?.toString() ?? '0';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomListScreen(buildingName: name)),
        ),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: appCardDecoration(radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconBadge(Icons.apartment_rounded, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HighlightText(
                          code,
                          query: query,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        HighlightText(
                          name,
                          query: query,
                          style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(description, style: TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4)),
              ],
              if (location != null && location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 15, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(location, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(icon: Icons.layers_outlined, label: '$floorCount ชั้น'),
                  _StatChip(icon: Icons.meeting_room_outlined, label: '$roomCount ห้อง'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
