import 'package:flutter/material.dart';

import 'api_client.dart';
import 'map_screen.dart';
import 'room_detail_screen.dart';
import 'room_utils.dart';
import 'skeleton.dart';
import 'widgets.dart';

class RoomListScreen extends StatefulWidget {
  final String buildingName;

  const RoomListScreen({super.key, required this.buildingName});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  late Future<List<Map<String, dynamic>>> _roomsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _floorFilter; // null = ทุกชั้น

  @override
  void initState() {
    super.initState();
    _roomsFuture = Api.roomsInBuilding(widget.buildingName);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = Api.roomsInBuilding(widget.buildingName);
    setState(() => _roomsFuture = future);
    try {
      await future;
    } catch (_) {
      // แสดงผลในหน้าจออยู่แล้ว
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.buildingName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'ดูบนแผนที่',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MapScreen(initialBuilding: widget.buildingName)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _roomsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SkeletonList.rooms(
              count: 6,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              header: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 50, radius: 14),
                  SizedBox(height: 12),
                  ChipRowSkeleton(widths: [76, 56, 56, 56]),
                  SectionTitleSkeleton(),
                ],
              ),
            );
          }
          if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _reload);

          final rooms = snapshot.data ?? const [];
          if (rooms.isEmpty) {
            return const StateView(
              icon: Icons.meeting_room_outlined,
              title: 'ยังไม่มีข้อมูลห้องเรียน',
              message: 'ยังไม่มีห้องเรียนในอาคารนี้ในระบบ',
            );
          }
          return _buildList(rooms);
        },
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> rooms) {
    final floors = sortFloors(rooms.map(floorOf));
    final activeFloor = floors.contains(_floorFilter) ? _floorFilter : null;

    final query = _query.toLowerCase();
    final filtered = rooms.where((room) {
      if (activeFloor != null && floorOf(room) != activeFloor) return false;
      if (query.isEmpty) return true;
      return (room['room_code']?.toString() ?? '').toLowerCase().contains(query);
    }).toList();
    final groups = groupByFloor(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: AppSearchField(
            controller: _searchController,
            hint: 'ค้นหารหัสห้องในอาคารนี้',
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        if (floors.length > 1)
          ChipRow(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            labels: ['ทั้งหมด', ...floors.map(floorLabel)],
            selected: activeFloor == null ? 'ทั้งหมด' : floorLabel(activeFloor),
            onSelected: (label) => setState(() {
              _floorFilter = label == 'ทั้งหมด' ? null : floors.firstWhere((f) => floorLabel(f) == label);
            }),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const StateView(
                  icon: Icons.search_off_rounded,
                  title: 'ไม่พบห้องที่ตรงกับเงื่อนไข',
                  message: 'ลองเปลี่ยนคำค้นหาหรือชั้นที่เลือก',
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      for (final group in groups) ...[
                        SectionTitle('${floorLabel(group.key)} · ${group.value.length} ห้อง'),
                        for (final (i, room) in group.value.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RoomTile(
                              room: room,
                              entranceIndex: i,
                              showBuilding: false,
                              highlight: _query,
                              onTap: () => openRoom(context, room),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
