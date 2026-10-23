import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_tabs.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'motion.dart';
import 'room_detail_screen.dart';
import 'room_utils.dart';
import 'skeleton.dart';
import 'widgets.dart';

class RoomListScreen extends StatefulWidget {
  final String buildingName;

  /// รหัสอาคาร (ถ้ามี) แสดงใต้ชื่อในแถบบน
  final String? buildingCode;

  const RoomListScreen({super.key, required this.buildingName, this.buildingCode});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  late Future<List<Map<String, dynamic>>> _roomsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _floorFilter; // null = ทุกชั้น
  int _roomTotal = 0;

  @override
  void initState() {
    super.initState();
    _roomsFuture = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rooms = await Api.roomsInBuilding(widget.buildingName);
    if (mounted) setState(() => _roomTotal = rooms.length);
    return rooms;
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _roomsFuture = future);
    try {
      await future;
    } catch (_) {
      // แสดงผลในหน้าจออยู่แล้ว
    }
  }

  void _openMap([String? floor]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MapScreen(initialBuilding: widget.buildingName, initialFloor: floor)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (widget.buildingCode != null && widget.buildingCode!.isNotEmpty) 'รหัสอาคาร ${widget.buildingCode}',
      if (_roomTotal > 0) '$_roomTotal ห้อง',
    ].join(' • ');

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(title: widget.buildingName, subtitle: subtitle, onMap: _openMap),
            Expanded(
              child: ColoredBox(
                color: AppColors.fill,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _roomsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return SkeletonList.rooms(
                        count: 6,
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        header: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(height: 50, radius: 999),
                            SizedBox(height: 12),
                            ChipRowSkeleton(widths: [76, 90, 90]),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> rooms) {
    final floors = sortFloors(rooms.map(floorOf));
    final activeFloor = floors.contains(_floorFilter) ? _floorFilter : null;
    final floorCounts = <String, int>{for (final room in rooms) floorOf(room): 0};
    for (final room in rooms) {
      floorCounts[floorOf(room)] = (floorCounts[floorOf(room)] ?? 0) + 1;
    }

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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: AppSearchField(
            pill: true,
            controller: _searchController,
            hint: 'ค้นหารหัสห้องในอาคารนี้ เช่น 201',
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        if (floors.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                PillButton(
                  label: 'ทั้งหมด',
                  icon: Icons.layers_rounded,
                  active: activeFloor == null,
                  onTap: () => setState(() => _floorFilter = null),
                ),
                for (final floor in floors) ...[
                  const SizedBox(width: 8),
                  PillButton(
                    label: '${floorLabel(floor)} (${floorCounts[floor]} ห้อง)',
                    active: activeFloor == floor,
                    onTap: () => setState(() => _floorFilter = floor),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 6),
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
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      for (final group in groups) ...[
                        _FloorHeader(
                          floor: group.key,
                          count: group.value.length,
                          onMap: group.key == '-' ? null : () => _openMap(group.key),
                        ),
                        for (final (i, room) in group.value.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RoomTile(
                              room: room,
                              entranceIndex: i,
                              showBuilding: false,
                              highlight: _query,
                              onTap: () => openRoom(context, room),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      _HelpCallout(
                        onSearch: () {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                          AppTabs.go(AppTabs.search);
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// แถบบน: ปุ่มย้อนกลับ + ชื่ออาคาร/รหัส และปุ่มสลับไปดูแผนที่
class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onMap;

  const _Header({required this.title, required this.subtitle, required this.onMap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'ย้อนกลับ',
            icon: Icon(Icons.arrow_back_rounded, color: AppColors.ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.2),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'ดูบนแผนที่',
            child: Material(
              color: AppColors.tint,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onMap,
                child: SizedBox(width: 38, height: 38, child: Icon(Icons.map_rounded, size: 20, color: AppColors.primary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// หัวข้อของแต่ละชั้น: แถบเขียวสั้น ๆ + "ชั้น 1 • 3 ห้อง" และปุ่มลัดไปแผนผังของชั้นนั้น
class _FloorHeader extends StatelessWidget {
  final String floor;
  final int count;
  final VoidCallback? onMap;

  const _FloorHeader({required this.floor, required this.count, required this.onMap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
      child: Row(
        children: [
          Container(width: 5, height: 16, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999))),
          const SizedBox(width: 8),
          Text(floorLabel(floor), style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          Text(' • $count ห้อง', style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
          const Spacer(),
          if (onMap != null)
            Pressable(
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: AppColors.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onMap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 13, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text('ดูผังชั้นนี้', style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ป้ายท้ายรายการ: หาห้องไม่เจอให้กลับไปค้นหา
class _HelpCallout extends StatelessWidget {
  final VoidCallback onSearch;

  const _HelpCallout({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.tint.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ไม่พบห้องที่ต้องการ?', style: TextStyle(color: AppColors.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text('ค้นหาจากทุกอาคารได้ที่หน้าค้นหา', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          TextButton(onPressed: onSearch, child: const Text('ไปค้นหา')),
        ],
      ),
    );
  }
}
