import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_prefs.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'panorama_screen.dart';
import 'room_detail_screen.dart';
import 'room_utils.dart';
import 'skeleton.dart';
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
  // เพิ่มค่าทุกครั้งที่ต้องการให้แผนที่ซูมไปที่ห้องที่เลือก (เช่น เลือกจากการค้นหา)
  int _focusToken = 0;

  // แผงข้อมูลห้องใต้แผนที่ ลากขึ้นเพื่อดูห้องทั้งชั้น ลากลงเพื่อเหลือแค่ห้องที่เลือก
  final DraggableScrollableController _sheet = DraggableScrollableController();
  ScrollController? _sheetScroll; // รายการในแผง ใช้เลื่อนกลับบนสุดตอนหุบ

  bool get _standalone => widget.initialBuilding != null;

  @override
  void initState() {
    super.initState();
    _buildingsFuture = Api.buildings();
    _floor = widget.initialFloor;
    _selectedId = widget.focusRoom?['id'];
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _moveSheet({required bool expand}) {
    if (!_sheet.isAttached) return;
    // หุบแล้วต้องเห็นห้องที่เลือกด้านบนสุดของแผง ไม่ใช่รายการที่เลื่อนค้างไว้
    final list = _sheetScroll;
    if (!expand && list != null && list.hasClients && list.offset > 0) list.jumpTo(0);
    final target = expand ? _sheetMax : _sheetMin;
    if (reduceMotion(context)) {
      _sheet.jumpTo(target);
    } else {
      _sheet.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  double _sheetMin = 0.3;
  static const _sheetMax = 0.9;
  static const _sheetPeek = 172.0; // ความสูงตอนหุบ (px) พอดีกับข้อมูลห้อง + ปุ่ม

  void _selectRoom(Map<String, dynamic> room) {
    setState(() => _selectedId = room['id']);
    _moveSheet(expand: false);
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

  /// เปิดช่องค้นหาห้อง แล้วพาแผนที่ไปยังอาคาร/ชั้นของห้องที่เลือก พร้อมซูมไปที่หมุด
  Future<void> _openSearch() async {
    final room = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _MapSearchSheet(),
    );
    if (room == null || !mounted) return;
    _goToRoom(room);
  }

  void _goToRoom(Map<String, dynamic> room) {
    final building = room['building_name']?.toString();
    if (building == null) return;
    Haptics.select();
    setState(() {
      if (building != _building) {
        _building = building;
        _roomsFuture = Api.roomsInBuilding(building);
      }
      _floor = floorOf(room);
      _selectedId = room['id'];
      _focusToken++;
    });
    if (!hasPin(room)) {
      showAppSnack(context, '${room['room_code'] ?? 'ห้องนี้'} ยังไม่ได้ปักหมุดบนแผนผัง แสดงชั้นของห้องให้แทน');
    }
  }

  void _reloadRooms() {
    setState(() => _roomsFuture = Api.roomsInBuilding(_building!));
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<List<Map<String, dynamic>>>(
      future: _buildingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const MapSkeleton();
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
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: names.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => PillButton(
                    label: names[index],
                    active: names[index] == _building,
                    icon: names[index] == _building ? Icons.domain_rounded : Icons.apartment_rounded,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    onTap: () => _selectBuilding(names[index]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(child: _buildRooms()),
          ],
        );
      },
    );

    if (_standalone) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('แผนที่'),
          actions: [
            IconButton(tooltip: 'ค้นหาห้องในแผนที่', icon: const Icon(Icons.search_rounded), onPressed: _openSearch),
            const SizedBox(width: 4),
          ],
        ),
        body: ColoredBox(color: AppColors.fill, child: Padding(padding: const EdgeInsets.only(top: 10), child: content)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTopBar(
          actions: [
            IconButton(
              tooltip: 'ค้นหาห้องในแผนที่',
              icon: Icon(Icons.search_rounded, color: AppColors.muted),
              onPressed: _openSearch,
            ),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: AppColors.fill,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INDOOR WAYFINDING',
                        style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'แผนที่ผังอาคาร',
                        style: TextStyle(color: AppColors.ink, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openFullscreen(List<Map<String, dynamic>> roomsOnFloor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenMap(
          building: _building!,
          floor: _floor!,
          rooms: roomsOnFloor,
          selectedId: _selectedId,
          onSelect: (room) => setState(() => _selectedId = room['id']),
        ),
      ),
    );
  }

  Widget _buildRooms() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _roomsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const MapSkeleton(showBuildingChips: false);
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
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 10),
                      child: Text('ระดับชั้น:', style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 20),
                        itemCount: floors.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final floor = floors[index];
                          return PillButton(
                            label: floorLabel(floor),
                            active: floor == _floor,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            onTap: () {
                              setState(() {
                                _floor = floor;
                                _selectedId = null;
                              });
                              // หุบหลังเฟรมถัดไป ให้เนื้อหาชั้นใหม่วาดเสร็จก่อน ไม่งั้นแอนิเมชันหุบโดนยกเลิก
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _moveSheet(expand: false);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  _sheetMin = (_sheetPeek / box.maxHeight).clamp(0.15, 0.6);
                  return Stack(
                    children: [
                      // แผนที่เว้นที่ด้านล่างให้แผงตอนหุบ หมุดจึงไม่ถูกแผงบัง
                      Positioned.fill(
                        bottom: _sheetPeek - 16,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _FloorPlanView(
                            key: ValueKey('$_building|$_floor'),
                            focusToken: _focusToken,
                            building: _building!,
                            floor: _floor!,
                            rooms: roomsOnFloor,
                            selectedId: selected?['id'],
                            onSelect: _selectRoom,
                            onFullscreen: () => _openFullscreen(roomsOnFloor),
                          ),
                        ),
                      ),
                      DraggableScrollableSheet(
                        controller: _sheet,
                        initialChildSize: _sheetMin,
                        minChildSize: _sheetMin,
                        maxChildSize: _sheetMax,
                        snap: true,
                        builder: (context, scrollController) => _RoomSheet(
                          scrollController: _sheetScroll = scrollController,
                          floor: _floor!,
                          rooms: roomsOnFloor,
                          selected: selected,
                          onPick: _selectRoom,
                          onShowAll: () => _moveSheet(expand: true),
                          onClear: () => setState(() => _selectedId = null),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// แผงค้นหาห้องในหน้าแผนที่ (ใช้ API ค้นหาเดียวกับแท็บค้นหา: รหัสห้อง ชื่ออาคาร ประเภทห้อง)
/// เลือกผลลัพธ์แล้วปิดแผงพร้อมส่งห้องนั้นกลับไปให้แผนที่พาไปยังหมุด
class _MapSearchSheet extends StatefulWidget {
  const _MapSearchSheet();

  @override
  State<_MapSearchSheet> createState() => _MapSearchSheetState();
}

class _MapSearchSheetState extends State<_MapSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  Object? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      _query = query;
      _error = null;
      _loading = query.isNotEmpty;
      if (query.isEmpty) _results = const [];
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await Api.searchRooms(query);
      if (!mounted || _query != query) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || _query != query) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ยกแผงขึ้นตามคีย์บอร์ด และสูงเกือบเต็มจอให้เห็นผลลัพธ์หลายรายการ
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ค้นหาห้องในแผนที่',
                    style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  AppSearchField(
                    controller: _controller,
                    hint: 'เช่น LH3-201, 80 ปี, ห้องบรรยาย',
                    autofocus: true,
                    onChanged: _onChanged,
                    onSubmitted: (_) {
                      if (_results.length == 1) Navigator.pop(context, _results.single);
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return const StateView(
        icon: Icons.travel_explore_rounded,
        title: 'พิมพ์เพื่อค้นหาห้อง',
        message: 'เลือกห้องแล้วแผนที่จะพาไปยังอาคาร ชั้น และหมุดของห้องนั้นให้',
      );
    }
    if (_loading && _results.isEmpty) return SkeletonList.rooms(count: 4, padding: const EdgeInsets.symmetric(horizontal: 20));
    if (_error != null) return StateView.error(_error!, onRetry: () => _onChanged(_query));
    if (_results.isEmpty) {
      return StateView(
        icon: Icons.search_off_rounded,
        title: 'ไม่พบผลลัพธ์ของ "$_query"',
        message: 'ลองค้นด้วยบางส่วนของรหัสห้อง ชื่ออาคาร หรือประเภทห้อง',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final room = _results[index];
        return RoomTile(
          room: room,
          entranceIndex: index,
          highlight: _query,
          icon: hasPin(room) ? Icons.location_on_rounded : Icons.meeting_room_outlined,
          onTap: () => Navigator.pop(context, room),
        );
      },
    );
  }
}

/// แผงข้อมูลห้องใต้แผนที่แบบลากขึ้น-ลงได้
/// หุบ: แสดงห้องที่เลือก (หรือปุ่มรายการห้อง/ภาพ 360°) / ลากขึ้น: แสดงห้องทั้งหมดในชั้นนี้
class _RoomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final String floor;
  final List<Map<String, dynamic>> rooms;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onPick;
  final VoidCallback onShowAll;
  final VoidCallback onClear;

  const _RoomSheet({
    required this.scrollController,
    required this.floor,
    required this.rooms,
    required this.selected,
    required this.onPick,
    required this.onShowAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // ที่จับลาก: บอกผู้ใช้ว่าแผงนี้ลากขึ้นได้
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          _MapFooter(
            floor: floor,
            rooms: rooms,
            selected: selected,
            onPick: onPick,
            embedded: true,
            onShowList: onShowAll,
            onClear: onClear,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ห้องทั้งหมดใน${floorLabel(floor)} (${rooms.length})',
                    style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                Text('แตะหมุดเพื่อดูห้อง', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ],
            ),
          ),
          for (final room in rooms)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RoomTile(
                room: room,
                showBuilding: false,
                icon: hasPin(room) ? Icons.location_on_rounded : Icons.meeting_room_outlined,
                // ห้องที่มีหมุด: เลือกบนแผนที่แล้วหุบแผง / ไม่มีหมุด: เปิดรายละเอียดห้องแทน
                onTap: () => hasPin(room) ? onPick(room) : openRoom(context, room),
              ),
            ),
        ],
      ),
    );
  }
}

/// แถบใต้แผนที่: แสดงห้องที่เลือกอยู่ (พร้อมปุ่มดูรายละเอียด) หรือปุ่มเปิดรายการห้องทั้งชั้น
class _MapFooter extends StatelessWidget {
  final String floor;
  final List<Map<String, dynamic>> rooms;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onPick;

  /// อยู่ในแผงลากได้ (ไม่ต้องเว้นขอบนอก) และใช้ [onShowList] แทนการเปิดหน้าต่างรายการห้อง
  final bool embedded;
  final VoidCallback? onShowList;

  /// ยกเลิกการเลือกห้อง (กลับไปแสดงปุ่มรายการห้อง/ภาพ 360°)
  final VoidCallback? onClear;

  const _MapFooter({
    required this.floor,
    required this.rooms,
    required this.selected,
    required this.onPick,
    this.embedded = false,
    this.onShowList,
    this.onClear,
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
      margin: embedded ? EdgeInsets.zero : const EdgeInsets.fromLTRB(20, 10, 20, 14),
      padding: room == null ? EdgeInsets.zero : const EdgeInsets.all(12),
      decoration: room == null ? const BoxDecoration() : appCardDecoration(color: AppColors.tint, radius: 18),
      child: room == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text(
                    pinned == 0 ? 'ชั้นนี้ยังไม่มีหมุดห้อง' : 'ปักหมุดบนแผนที่แล้ว $pinned จาก ${rooms.length} ห้อง',
                    style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
                  ),
                ),
                // แถบสลับแบบแคปซูล: "รายการห้อง" (ขยายแผงดูห้องทั้งชั้น) / "ภาพ 360°" (รายการห้องที่มีภาพ)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentButton(
                          icon: Icons.format_list_bulleted_rounded,
                          label: 'รายการห้อง',
                          active: true,
                          onTap: onShowList ?? () => _openList(context),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _SegmentButton(
                          icon: Icons.threesixty_rounded,
                          label: count360 == 0 ? 'ภาพ 360°' : 'ภาพ 360° ($count360)',
                          active: false,
                          onTap: () => _open360List(context),
                        ),
                      ),
                    ],
                  ),
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
                    if (onClear != null)
                      IconButton(
                        tooltip: 'ยกเลิกการเลือก',
                        icon: Icon(Icons.close_rounded, color: AppColors.muted),
                        onPressed: onClear,
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

/// ปุ่มในแถบสลับแคปซูลใต้แผนที่ (ตัวที่ active เป็นแผ่นขาวตัวหนังสือเขียว)
class _SegmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegmentButton({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.muted;
    return Material(
      color: active ? AppColors.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      elevation: active ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: active ? FontWeight.w800 : FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// โหลดรูปผังของอาคาร+ชั้น แล้ววาดหมุดตามตำแหน่ง % ของแต่ละห้อง
/// พื้นที่ซูม/เลื่อนครอบทั้งกรอบการ์ด (ไม่ใช่แค่ขนาดรูป) จึงลากรูปที่ซูมแล้วไปใช้พื้นที่ว่างได้
/// ถ้าตอนสร้างมีห้องที่เลือกอยู่ (เช่น มาจากหน้ารายละเอียดห้อง) จะซูมเข้าไปที่หมุดห้องนั้นให้เอง
class _FloorPlanView extends StatefulWidget {
  final String building;
  final String floor;
  final List<Map<String, dynamic>> rooms;
  final Object? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback? onFullscreen;

  /// เปลี่ยนค่าเมื่อต้องการให้ซูมไปที่ห้องที่เลือกอีกครั้ง (กรณีอยู่ชั้นเดิมอยู่แล้ว)
  final int focusToken;

  const _FloorPlanView({
    super.key,
    required this.building,
    required this.floor,
    required this.rooms,
    required this.selectedId,
    required this.onSelect,
    this.onFullscreen,
    this.focusToken = 0,
  });

  @override
  State<_FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends State<_FloorPlanView> with SingleTickerProviderStateMixin {
  static const _maxScale = 6.0;
  static const _focusScale = 2.2;

  late Future<FloorPlan?> _future;
  final TransformationController _controller = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Animation<Matrix4>? _tween;

  // ขนาดกรอบและตำแหน่งรูปในกรอบ (คำนวณตอนจัดวางล่าสุด) ใช้คำนวณการซูม
  Size _viewport = Size.zero;
  Rect _imageRect = Rect.zero;
  late Object? _focusId = widget.selectedId;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _future = Api.floorPlan(widget.building, widget.floor);
    _anim.addListener(() {
      final tween = _tween;
      if (tween != null) _controller.value = tween.value;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = Api.floorPlan(widget.building, widget.floor));

  double get _scale => _controller.value.getMaxScaleOnAxis();

  /// matrix ที่ซูมระดับ [scale] โดยให้จุด [scene] (พิกัดในกรอบ) อยู่กลางจอ และไม่เลื่อนจนเห็นขอบว่าง
  Matrix4 _matrixFor(double scale, Offset scene) {
    if (scale <= 1.0001) return Matrix4.identity();
    final w = _viewport.width;
    final h = _viewport.height;
    final tx = (w / 2 - scale * scene.dx).clamp(w - scale * w, 0.0);
    final ty = (h / 2 - scale * scene.dy).clamp(h - scale * h, 0.0);
    return Matrix4(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  void _animateTo(Matrix4 target) {
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = target;
      return;
    }
    _tween = Matrix4Tween(begin: _controller.value, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  void _zoomBy(double factor) {
    final center = _controller.toScene(Offset(_viewport.width / 2, _viewport.height / 2));
    _animateTo(_matrixFor((_scale * factor).clamp(1.0, _maxScale), center));
  }

  Offset _pinOffset(Map<String, dynamic> room) {
    final x = (double.tryParse('${room['pin_x']}') ?? 0) / 100;
    final y = (double.tryParse('${room['pin_y']}') ?? 0) / 100;
    return Offset(_imageRect.left + _imageRect.width * x, _imageRect.top + _imageRect.height * y);
  }

  @override
  void didUpdateWidget(covariant _FloorPlanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusToken != oldWidget.focusToken) {
      _focusId = widget.selectedId;
      _focused = false; // ซูมใหม่ตอนจัดวางรอบถัดไป
    }
  }

  void _focusSelectedOnce() {
    if (_focused || _focusId == null) return;
    _focused = true;
    for (final room in widget.rooms) {
      if (room['id'] == _focusId && hasPin(room)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _animateTo(_matrixFor(_focusScale, _pinOffset(room)));
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FloorPlan?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Shimmer(child: SkeletonBox(radius: 16));
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
      decoration: appCardDecoration(radius: 20).copyWith(
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // รูปพอดีกรอบตามสัดส่วนจริง วางกึ่งกลาง ส่วนพื้นที่ซูมเท่ากับทั้งกรอบ
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          var iw = w;
          var ih = iw / plan.aspectRatio;
          if (ih > h) {
            ih = h;
            iw = ih * plan.aspectRatio;
          }
          _viewport = Size(w, h);
          _imageRect = Rect.fromLTWH((w - iw) / 2, (h - ih) / 2, iw, ih);
          _focusSelectedOnce();

          return Stack(
            children: [
              InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: _maxScale,
                onInteractionStart: (_) => _anim.stop(),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: _imageRect,
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
                          key: ValueKey('pin-${room['id'] ?? room['room_code']}'),
                          room: room,
                          position: _pinOffset(room),
                          controller: _controller,
                          selected: room['id'] == widget.selectedId,
                          onTap: () {
                            Haptics.select();
                            widget.onSelect(room);
                          },
                        ),
                      // ป้ายชื่อวาดเป็นชั้นแยกทับหมุดทั้งหมด จะได้ไม่โดนหมุดที่อยู่ใกล้กันบัง
                      for (final room in pinned)
                        _PinMarker(
                          key: ValueKey('label-${room['id'] ?? room['room_code']}'),
                          room: room,
                          position: _pinOffset(room),
                          controller: _controller,
                          selected: room['id'] == widget.selectedId,
                          onTap: () {},
                          labelsOnly: true,
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.onFullscreen != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _MapButton(
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'เต็มจอ',
                    onTap: widget.onFullscreen!,
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Column(
                  children: [
                    _MapButton(icon: Icons.add_rounded, tooltip: 'ซูมเข้า', onTap: () => _zoomBy(1.6)),
                    const SizedBox(height: 6),
                    _MapButton(icon: Icons.remove_rounded, tooltip: 'ซูมออก', onTap: () => _zoomBy(1 / 1.6)),
                    const SizedBox(height: 6),
                    _MapButton(
                      icon: Icons.center_focus_strong_rounded,
                      tooltip: 'รีเซ็ตมุมมอง',
                      onTap: () => _animateTo(Matrix4.identity()),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ปุ่มกลมเล็กบนแผนที่ (ซูม/รีเซ็ต/เต็มจอ)
class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: CircleBorder(side: BorderSide(color: AppColors.line)),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 19,
        color: AppColors.muted,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        icon: Icon(icon),
        onPressed: onTap,
      ),
    );
  }
}

/// แผนที่แบบเต็มจอ: ชั้นเดียวกับที่เปิดมา ไม่มีหัวข้อ/ชิปเลือกชั้น ให้พื้นที่แผนผังมากที่สุด
/// เลือกหมุดในหน้านี้แล้วหน้าแผนที่ปกติจะเลือกห้องเดียวกันตามไปด้วย (ผ่าน onSelect)
class _FullscreenMap extends StatefulWidget {
  final String building;
  final String floor;
  final List<Map<String, dynamic>> rooms;
  final Object? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const _FullscreenMap({
    required this.building,
    required this.floor,
    required this.rooms,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  State<_FullscreenMap> createState() => _FullscreenMapState();
}

class _FullscreenMapState extends State<_FullscreenMap> {
  late Object? _selectedId = widget.selectedId;

  void _select(Map<String, dynamic> room) {
    setState(() => _selectedId = room['id']);
    widget.onSelect(room);
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selected;
    for (final room in widget.rooms) {
      if (room['id'] != null && room['id'] == _selectedId) selected = room;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'ปิดเต็มจอ',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(floorLabel(widget.floor)),
            Text(
              widget.building,
              style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _FloorPlanView(
                  building: widget.building,
                  floor: widget.floor,
                  rooms: widget.rooms,
                  selectedId: _selectedId,
                  onSelect: _select,
                ),
              ),
            ),
            _MapFooter(floor: widget.floor, rooms: widget.rooms, selected: selected, onPick: _select),
          ],
        ),
      ),
    );
  }
}

/// หมุดห้อง: ขนาดคงที่บนหน้าจอแม้ซูมแผนที่ (ชดเชยด้วย 1/scale) และไฮไลต์ + ป้ายชื่อเมื่อถูกเลือก
/// เมื่อซูมเข้าเกิน [_labelFrom] ทุกหมุดจะค่อย ๆ แสดงป้ายรหัสห้อง (ตอนซูมออกซ่อนไว้กันป้ายทับกัน)
class _PinMarker extends StatelessWidget {
  final Map<String, dynamic> room;
  final Offset position;
  final TransformationController controller;
  final bool selected;
  final VoidCallback onTap;
  final bool labelsOnly;

  const _PinMarker({
    super.key,
    required this.room,
    required this.position,
    required this.controller,
    required this.selected,
    required this.onTap,
    this.labelsOnly = false,
  });

  static const _hitSize = 44.0;
  static const _labelFrom = 1.8; // เริ่มแสดงป้ายที่ระดับซูมนี้
  static const _labelFull = 2.3; // ป้ายชัดเต็มที่ระดับซูมนี้

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - _hitSize / 2,
      top: position.dy - _hitSize / 2,
      width: _hitSize,
      height: _hitSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, AppPrefs.alwaysShowLabels]),
        builder: (_, _) {
          final scale = controller.value.getMaxScaleOnAxis();
          // ตั้งค่า "แสดงชื่อห้องตลอดเวลา" เปิดอยู่ = ป้ายชัดเต็มที่ทุกระดับซูม
          final labelOpacity = AppPrefs.alwaysShowLabels.value
              ? 1.0
              : ((scale - _labelFrom) / (_labelFull - _labelFrom)).clamp(0.0, 1.0);
          return Transform.scale(scale: 1 / scale, child: _buildPin(labelOpacity));
        },
      ),
    );
  }

  Widget _buildPin(double labelOpacity) {
    if (labelsOnly) return IgnorePointer(child: _buildLabel(labelOpacity));

    final maintenance = isMaintenance(room);
    final dotSize = selected ? 26.0 : 18.0;
    final color = maintenance ? AppColors.warning : (selected ? AppColors.primaryDark : AppColors.primary);

    return GestureDetector(
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
        ],
      ),
    );
  }

  /// ชั้นป้ายชื่อ: ห้องที่เลือก = ป้ายเข้มเสมอ, ห้องอื่น = ป้ายขาวเมื่อซูมเข้า
  Widget _buildLabel(double labelOpacity) {
    final code = room['room_code']?.toString() ?? '';
    if (code.isEmpty || (!selected && labelOpacity <= 0)) return const SizedBox.shrink();

    final label = selected
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
            child: Text(
              code,
              maxLines: 1,
              style: TextStyle(color: AppColors.background, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          )
        : Opacity(
            opacity: labelOpacity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.line),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))],
              ),
              child: Text(
                code,
                maxLines: 1,
                style: TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: _hitSize / 2 + (selected ? 12 : 8),
          left: -60,
          right: -60,
          child: Center(child: label),
        ),
      ],
    );
  }
}