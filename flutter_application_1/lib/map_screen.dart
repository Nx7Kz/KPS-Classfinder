import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'panorama_screen.dart';
import 'room_detail_screen.dart';
import 'room_utils.dart';
import 'widgets.dart';

/// แผนที่ผังชั้นของอาคาร: เลือกอาคาร → เลือกชั้น → แตะหมุดเพื่อดูห้อง
/// ถ้าเปิดจากหน้าอื่น (ส่ง initialBuilding) จะแสดงเป็นหน้าเต็มพร้อมปุ่มย้อนกลับ
/// และถ้าส่ง focusRoom มาด้วยจะเลือก/ไฮไลต์หมุดของห้องนั้นให้ทันที
class MapScreen extends StatefulWidget {
  final String? initialBuilding;
  final String? initialFloor;
  final Map<String, dynamic>? focusRoom;

  const MapScreen({super.key, this.initialBuilding, this.initialFloor, this.focusRoom});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late Future<List<Map<String, dynamic>>> _buildingsFuture;
  Future<List<Map<String, dynamic>>>? _roomsFuture;

  String? _building;
  String? _floor;
  Object? _selectedId;

  bool get _standalone => widget.initialBuilding != null;

  @override
  void initState() {
    super.initState();
    _buildingsFuture = Api.buildings();
    _floor = widget.initialFloor;
    _selectedId = widget.focusRoom?['id'];
  }

  void _retry() {
    setState(() {
      _buildingsFuture = Api.buildings();
      _roomsFuture = null;
    });
  }

  void _selectBuilding(String building) {
    if (building == _building) return;
    setState(() {
      _building = building;
      _floor = null;
      _selectedId = null;
      _roomsFuture = Api.roomsInBuilding(building);
    });
  }

  void _reloadRooms() {
    setState(() => _roomsFuture = Api.roomsInBuilding(_building!));
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<List<Map<String, dynamic>>>(
      future: _buildingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
        if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _retry);

        final names = (snapshot.data ?? const []).map((b) => b['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
        if (names.isEmpty) {
          return const StateView(
            icon: Icons.map_outlined,
            title: 'ยังไม่มีอาคารในระบบ',
            message: 'รอผู้ดูแลเพิ่มข้อมูลอาคารและแผนที่',
          );
        }

        if (_building == null || !names.contains(_building)) {
          _building = names.contains(widget.initialBuilding) ? widget.initialBuilding : names.first;
          _roomsFuture = Api.roomsInBuilding(_building!);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (names.length > 1) ...[
              ChipRow(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                labels: names,
                selected: _building,
                onSelected: _selectBuilding,
              ),
              const SizedBox(height: 10),
            ],
            Expanded(child: _buildRooms()),
          ],
        );
      },
    );

    if (_standalone) {
      return Scaffold(appBar: AppBar(title: const Text('แผนที่')), body: content);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: PageHeader(title: 'แผนที่', subtitle: 'เลือกอาคารและชั้น แล้วแตะหมุดเพื่อดูห้อง'),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildRooms() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _roomsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
        if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _reloadRooms);

        final rooms = snapshot.data ?? const [];
        if (rooms.isEmpty) {
          return const StateView(
            icon: Icons.meeting_room_outlined,
            title: 'ยังไม่มีข้อมูลห้องเรียน',
            message: 'ยังไม่มีห้องเรียนในอาคารนี้ในระบบ',
          );
        }

        final floors = sortFloors(rooms.map(floorOf));
        if (_floor == null || !floors.contains(_floor)) _floor = floors.first;

        final roomsOnFloor = rooms.where((room) => floorOf(room) == _floor).toList();
        Map<String, dynamic>? selected;
        for (final room in roomsOnFloor) {
          if (room['id'] != null && room['id'] == _selectedId) selected = room;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (floors.length > 1) ...[
              ChipRow(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                labels: floors.map(floorLabel).toList(),
                selected: floorLabel(_floor!),
                onSelected: (label) => setState(() {
                  _floor = floors.firstWhere((f) => floorLabel(f) == label);
                  _selectedId = null;
                }),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FloorPlanView(
                  key: ValueKey('$_building|$_floor'),
                  building: _building!,
                  floor: _floor!,
                  rooms: roomsOnFloor,
                  selectedId: selected?['id'],
                  onSelect: (room) => setState(() => _selectedId = room['id']),
                ),
              ),
            ),
            _MapFooter(
              floor: _floor!,
              rooms: roomsOnFloor,
              selected: selected,
              onPick: (room) => setState(() => _selectedId = room['id']),
            ),
          ],
        );
      },
    );
  }
}

/// แถบใต้แผนที่: แสดงห้องที่เลือกอยู่ (พร้อมปุ่มดูรายละเอียด) หรือปุ่มเปิดรายการห้องทั้งชั้น
class _MapFooter extends StatelessWidget {
  final String floor;
  final List<Map<String, dynamic>> rooms;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onPick;

  const _MapFooter({
    required this.floor,
    required this.rooms,
    required this.selected,
    required this.onPick,
  });

  /// only360 = true: แสดงเฉพาะห้องที่มีภาพ 360° แล้วแตะเพื่อเปิดภาพได้เลย
  void _openList(BuildContext context, {bool only360 = false}) {
    final shown = only360 ? rooms.where(hasPanorama).toList() : rooms;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              only360
                  ? 'ภาพ 360° · ${floorLabel(floor)} (${shown.length} ห้อง)'
                  : '${floorLabel(floor)} · ${rooms.length} ห้อง',
              style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final room in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RoomTile(
                  room: room,
                  showBuilding: false,
                  icon: only360
                      ? Icons.threesixty_rounded
                      : (hasPin(room) ? Icons.location_on_rounded : Icons.meeting_room_outlined),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (only360) {
                      openPanorama(context, room);
                    } else if (hasPin(room)) {
                      onPick(room);
                    } else {
                      openRoom(context, room);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _open360List(BuildContext context) {
    if (!rooms.any(hasPanorama)) {
      showAppSnack(context, 'ชั้นนี้ยังไม่มีภาพ 360°');
      return;
    }
    _openList(context, only360: true);
  }

  @override
  Widget build(BuildContext context) {
    final pinned = rooms.where(hasPin).length;
    final count360 = rooms.where(hasPanorama).length;
    final room = selected;
    final smallButton = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      backgroundColor: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      padding: const EdgeInsets.all(12),
      decoration: appCardDecoration(color: room == null ? AppColors.fill : AppColors.tint, radius: 18),
      child: room == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                  child: Text(
                    pinned == 0
                        ? 'ชั้นนี้ยังไม่มีหมุดห้อง'
                        : 'แตะหมุดบนแผนที่เพื่อดูห้อง ($pinned จาก ${rooms.length} ห้องมีหมุด)',
                    style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: smallButton,
                        onPressed: () => _openList(context),
                        icon: const Icon(Icons.list_rounded, size: 18),
                        label: const Text('รายการห้อง', maxLines: 1, softWrap: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          backgroundColor: count360 == 0 ? AppColors.muted : AppColors.primary,
                        ),
                        onPressed: () => _open360List(context),
                        icon: const Icon(Icons.threesixty_rounded, size: 20),
                        label: Text(
                          count360 == 0 ? 'ภาพ 360°' : 'ภาพ 360° ($count360)',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconBadge(Icons.location_on_rounded, size: 42, background: AppColors.surface),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room['room_code']?.toString() ?? '-',
                            style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            roomSummary(room) ?? floorLabel(floor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (hasPanorama(room)) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: smallButton,
                          onPressed: () => openPanorama(context, room),
                          icon: const Icon(Icons.threesixty_rounded, size: 20),
                          label: const Text('ภาพ 360°', maxLines: 1, softWrap: false),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: () => openRoom(context, room),
                        child: const Text('รายละเอียด'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// โหลดรูปผังของอาคาร+ชั้น แล้ววาดหมุดตามตำแหน่ง % ของแต่ละห้อง
class _FloorPlanView extends StatefulWidget {
  final String building;
  final String floor;
  final List<Map<String, dynamic>> rooms;
  final Object? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const _FloorPlanView({
    super.key,
    required this.building,
    required this.floor,
    required this.rooms,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  State<_FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends State<_FloorPlanView> {
  late Future<FloorPlan?> _future;
  final TransformationController _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _future = Api.floorPlan(widget.building, widget.floor);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = Api.floorPlan(widget.building, widget.floor));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FloorPlan?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
        if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _reload);

        final plan = snapshot.data;
        if (plan == null) {
          return Container(
            decoration: appCardDecoration(color: AppColors.fill),
            child: const StateView(
              icon: Icons.map_outlined,
              title: 'ยังไม่มีแผนที่สำหรับชั้นนี้',
              message: 'ยังดูรายชื่อห้องของชั้นนี้ได้จากปุ่ม "รายการห้อง"',
            ),
          );
        }
        return _buildMap(plan);
      },
    );
  }

  Widget _buildMap(FloorPlan plan) {
    final pinned = widget.rooms.where(hasPin).toList();
    // วาดหมุดที่เลือกไว้เป็นอันสุดท้ายเพื่อให้อยู่บนสุด
    pinned.sort((a, b) {
      final aSel = a['id'] == widget.selectedId ? 1 : 0;
      final bSel = b['id'] == widget.selectedId ? 1 : 0;
      return aSel.compareTo(bSel);
    });

    return Container(
      decoration: appCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // คำนวณกรอบให้พอดีสัดส่วนภาพก่อนส่งเข้า InteractiveViewer (มันบังคับให้ลูกเต็มกรอบเสมอ)
          var width = constraints.maxWidth;
          var height = width / plan.aspectRatio;
          if (height > constraints.maxHeight) {
            height = constraints.maxHeight;
            width = height * plan.aspectRatio;
          }

          return Stack(
            children: [
              Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: InteractiveViewer(
                    transformationController: _controller,
                    minScale: 1,
                    maxScale: 5,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.network(
                            plan.imageUrl,
                            fit: BoxFit.fill,
                            errorBuilder: (_, _, _) => Center(
                              child: Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 40),
                            ),
                          ),
                        ),
                        for (final room in pinned)
                          _PinMarker(
                            key: ValueKey(room['id'] ?? room['room_code']),
                            room: room,
                            mapSize: Size(width, height),
                            controller: _controller,
                            selected: room['id'] == widget.selectedId,
                            onTap: () => widget.onSelect(room),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: AppColors.surface,
                  shape: CircleBorder(side: BorderSide(color: AppColors.line)),
                  child: IconButton(
                    tooltip: 'รีเซ็ตมุมมอง',
                    iconSize: 20,
                    color: AppColors.primary,
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    onPressed: () => _controller.value = Matrix4.identity(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// หมุดห้อง: ขนาดคงที่บนหน้าจอแม้ซูมแผนที่ (ชดเชยด้วย 1/scale) และไฮไลต์ + ป้ายชื่อเมื่อถูกเลือก
class _PinMarker extends StatelessWidget {
  final Map<String, dynamic> room;
  final Size mapSize;
  final TransformationController controller;
  final bool selected;
  final VoidCallback onTap;

  const _PinMarker({
    super.key,
    required this.room,
    required this.mapSize,
    required this.controller,
    required this.selected,
    required this.onTap,
  });

  static const _hitSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final x = double.tryParse('${room['pin_x']}') ?? 0;
    final y = double.tryParse('${room['pin_y']}') ?? 0;
    final maintenance = isMaintenance(room);
    final dotSize = selected ? 26.0 : 18.0;
    final color = maintenance ? AppColors.muted : (selected ? AppColors.primaryDark : AppColors.primary);

    return Positioned(
      left: mapSize.width * (x / 100) - _hitSize / 2,
      top: mapSize.height * (y / 100) - _hitSize / 2,
      width: _hitSize,
      height: _hitSize,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, child) => Transform.scale(
          scale: 1 / controller.value.getMaxScaleOnAxis(),
          child: child,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (selected)
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: maintenance ? Icon(Icons.build_rounded, size: 10, color: AppColors.background) : null,
              ),
              // ป้าย 360° เล็ก ๆ มุมหมุด บอกว่าห้องนี้มีภาพพาโนรามา
              if (hasPanorama(room))
                Positioned(
                  top: selected ? 3 : 6,
                  right: selected ? 3 : 6,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 1.2),
                    ),
                    child: Icon(Icons.threesixty_rounded, size: 10, color: AppColors.primary),
                  ),
                ),
              if (selected)
                Positioned(
                  bottom: _hitSize / 2 + 12,
                  left: -60,
                  right: -60,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        room['room_code']?.toString() ?? '',
                        maxLines: 1,
                        style: TextStyle(color: AppColors.background, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
