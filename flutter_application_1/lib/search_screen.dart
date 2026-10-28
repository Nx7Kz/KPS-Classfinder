import 'dart:async';

import 'package:flutter/material.dart';

import 'announcements.dart';
import 'api_client.dart';
import 'app_tabs.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'open_status.dart';
import 'room_detail_screen.dart';
import 'building_detail_screen.dart';
import 'room_store.dart';
import 'room_utils.dart';
import 'saved_screen.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// คำค้นลัดตามประเภทห้อง (ค้นได้จากฟิลด์ประเภทห้องอยู่แล้ว จึงแตะแล้วค้นต่อได้ทันที)
const _roomTypeShortcuts = ['ห้องบรรยาย'];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  List<Map<String, dynamic>> _results = const [];
  bool _isSearching = false;
  Object? _searchError;

  List<Map<String, dynamic>> _recents = const [];
  List<Map<String, dynamic>> _favorites = const [];
  List<Map<String, dynamic>> _buildings = const [];
  late Future<List<Map<String, dynamic>>> _buildingsFuture;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
    RoomStore.revision.addListener(_loadSaved);
    ClosureStore.revision.addListener(_onClosuresChanged);
    _loadSaved();
  }

  // วันปิดพิเศษโหลดเสร็จ/เปลี่ยน -> คำนวณประกาศใหม่
  void _onClosuresChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    RoomStore.revision.removeListener(_loadSaved);
    ClosureStore.revision.removeListener(_onClosuresChanged);
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadBuildings() {
    final future = Api.buildings();
    _buildingsFuture = future;
    // เก็บรายการไว้ใช้กับชิปกรอง/รหัสอาคารบนการ์ดห้อง (ข้อผิดพลาดไปแสดงที่ส่วน "เลือกจากอาคาร" อยู่แล้ว)
    future.then((list) {
      if (mounted) setState(() => _buildings = list);
    }, onError: (_) {});
  }

  Future<void> _loadSaved() async {
    final recents = await RoomStore.loadRecents();
    final favorites = await RoomStore.loadFavorites();
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _favorites = favorites;
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _isSearching = false;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _query = query;
      _isSearching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await Api.searchRooms(query);
      if (!mounted || _query != query) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || _query != query) return;
      setState(() {
        _results = const [];
        _isSearching = false;
        _searchError = error;
      });
    }
  }

  /// กด Enter: ถ้าเจอห้องเดียวเปิดรายละเอียดเลย ไม่งั้นค้างรายการให้เลือก
  Future<void> _submit(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    setState(() {
      _query = query;
      _isSearching = true;
      _searchError = null;
    });
    await _runSearch(query);
    if (!mounted || _results.length != 1) return;
    _focusNode.unfocus();
    openRoom(context, _results.single);
  }

  /// แตะชิป: ใส่คำค้นลงช่องแล้วค้นทันที (ชิป "ทั้งหมด" = ล้างคำค้น)
  void _applyShortcut(String? term) {
    _focusNode.unfocus();
    _controller.text = term ?? '';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _onChanged(_controller.text);
    if (term != null) _runSearch(term);
  }

  void _retryBuildings() {
    setState(_loadBuildings);
  }

  String? _buildingCode(Map<String, dynamic> room) {
    final name = room['building_name']?.toString();
    for (final building in _buildings) {
      if (building['name']?.toString() == name) return building['code']?.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    final announcements = buildAnnouncements(_buildings);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _focusNode.unfocus(),
      child: Column(
        children: [
          AppTopBar(
            actions: [
              IconButton(
                tooltip: 'ประกาศ',
                onPressed: () => openAnnouncements(context),
                icon: Badge(
                  isLabelVisible: announcements.isNotEmpty,
                  label: Text('${announcements.length}'),
                  backgroundColor: announcements.any((item) => item.urgent) ? AppColors.warning : AppColors.primary,
                  child: Icon(Icons.notifications_none_rounded, color: AppColors.muted),
                ),
              ),
              IconButton(
                tooltip: 'ห้องที่บันทึกไว้',
                onPressed: () => openSaved(context),
                icon: Icon(Icons.bookmarks_outlined, color: AppColors.muted),
              ),
            ],
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.fill,
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  const PageHeader(
                    title: 'ค้นหาห้องเรียน',
                    subtitle: 'ค้นด้วยรหัสห้อง ชื่ออาคาร หรือประเภทห้อง แล้วดูตำแหน่งบนแผนที่ได้ทันที',
                  ),
                  const SizedBox(height: 18),
                  AppSearchField(
                    pill: true,
                    controller: _controller,
                    focusNode: _focusNode,
                    hint: 'เช่น LH3-201, 80 ปี, ห้องบรรยาย',
                    onChanged: _onChanged,
                    onSubmitted: _submit,
                  ),
                  const SizedBox(height: 14),
                  _ShortcutChips(
                    selected: _query,
                    terms: [
                      for (final building in _buildings) building['name']?.toString() ?? '',
                      ..._roomTypeShortcuts,
                    ].where((term) => term.isNotEmpty).toList(),
                    onPick: _applyShortcut,
                  ),
                  if (searching)
                    ..._buildResults()
                  else ...[
                    ..._buildAnnouncements(announcements),
                    ..._buildBuildingShortcuts(),
                    ..._buildFavorites(),
                    ..._buildRecents(),
                    const SizedBox(height: 24),
                    _WayfindingBanner(onTap: () => AppTabs.go(AppTabs.map)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResults() {
    if (_isSearching && _results.isEmpty) {
      return [const SectionTitleSkeleton(width: 110), SkeletonList.rooms(count: 4)];
    }

    if (_searchError != null) {
      return [
        SizedBox(
          height: 260,
          child: StateView.error(_searchError!, onRetry: () => _runSearch(_query)),
        ),
      ];
    }

    if (_results.isEmpty) {
      return [
        SizedBox(
          height: 240,
          child: StateView(
            icon: Icons.search_off_rounded,
            title: 'ไม่พบผลลัพธ์ของ "$_query"',
            message: 'ลองตรวจสอบตัวสะกด หรือค้นด้วยบางส่วนของรหัสห้อง ชื่ออาคาร หรือประเภทห้อง',
          ),
        ),
      ];
    }

    return [
      SectionTitle('ผลการค้นหา (${_results.length})'),
      for (final (i, room) in _results.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RoomTile(
            room: room,
            entranceIndex: i,
            highlight: _query,
            onTap: () {
              _focusNode.unfocus();
              openRoom(context, room);
            },
          ),
        ),
    ];
  }

  /// ห้องโปรด (เดิมอยู่ในแท็บ "บันทึก") แสดงเป็นการ์ดเล็กสองคอลัมน์ ดูทั้งหมด/นำออกได้ที่ "ดูทั้งหมด"
  List<Widget> _buildFavorites() {
    if (_favorites.isEmpty) return const [];

    return [
      SectionTitle(
        'ห้องโปรด',
        trailing: _LinkButton(label: 'ดูทั้งหมด', onTap: () => openSaved(context)),
      ),
      _MiniRoomGrid(
        rooms: _favorites,
        codeOf: _buildingCode,
        trailingIcon: Icons.star_rounded,
        onOpen: (room) => openRoom(context, room),
      ),
    ];
  }

  List<Widget> _buildRecents() {
    if (_recents.isEmpty) return const [];

    return [
      SectionTitle(
        'ดูล่าสุด',
        trailing: _LinkButton(label: 'ล้าง', onTap: RoomStore.clearRecents, muted: true),
      ),
      _MiniRoomGrid(
        rooms: _recents,
        codeOf: _buildingCode,
        trailingIcon: Icons.close_rounded,
        trailingTooltip: 'ลบออกจากประวัติ',
        onTrailing: (room) {
          Haptics.tap();
          RoomStore.removeRecent(room);
        },
        onOpen: (room) => openRoom(context, room),
      ),
    ];
  }

  /// ประกาศสำคัญ (วันปิดทำการ/ห้องปิดปรับปรุง) แสดงสูงสุด 2 รายการ ที่เหลือดูในหน้าประกาศ
  List<Widget> _buildAnnouncements(List<Announcement> items) {
    if (items.isEmpty) return const [];
    return [
      SectionTitle(
        'ประกาศ',
        trailing: _LinkButton(label: items.length > 2 ? 'ดูทั้งหมด (${items.length})' : 'ดูทั้งหมด', onTap: () => openAnnouncements(context)),
      ),
      for (final item in items.take(2))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AnnouncementTile(
            item: item,
            onTap: item.building == null ? () => openAnnouncements(context) : () => openAnnouncementTarget(context, item),
          ),
        ),
    ];
  }

  List<Widget> _buildBuildingShortcuts() {
    return [
      SectionTitle(
        'เลือกจากอาคาร',
        trailing: _buildings.isEmpty
            ? null
            : _LinkButton(label: 'ดูทั้งหมด (${_buildings.length} อาคาร)', onTap: () => AppTabs.go(AppTabs.places)),
      ),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _buildingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SkeletonList(count: 2, itemBuilder: (_) => const RoomTileSkeleton(titleWidth: 160));
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 240,
              child: StateView.error(snapshot.error!, onRetry: _retryBuildings),
            );
          }
          final buildings = snapshot.data ?? const [];
          if (buildings.isEmpty) {
            return const SizedBox(
              height: 200,
              child: StateView(
                icon: Icons.apartment_outlined,
                title: 'ยังไม่มีอาคารในระบบ',
                message: 'รอผู้ดูแลเพิ่มข้อมูลอาคาร',
              ),
            );
          }
          return Column(
            children: [
              for (final building in buildings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Pressable(child: _BuildingShortcut(building: building)),
                ),
            ],
          );
        },
      ),
    ];
  }
}

/// ชิปคำค้นลัด: "ทั้งหมด" + ชื่ออาคาร + ประเภทห้อง เลื่อนแนวนอนได้ ชิปที่ตรงกับคำค้นตอนนี้เป็นสีเขียวเต็ม
class _ShortcutChips extends StatelessWidget {
  final String selected;
  final List<String> terms;
  final ValueChanged<String?> onPick;

  const _ShortcutChips({required this.selected, required this.terms, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          PillButton(label: 'ทั้งหมด', active: selected.isEmpty, onTap: () => onPick(null)),
          for (final term in terms) ...[
            const SizedBox(width: 8),
            PillButton(label: term, active: selected.toLowerCase() == term.toLowerCase(), onTap: () => onPick(term)),
          ],
        ],
      ),
    );
  }
}

/// ลิงก์ตัวหนังสือเล็กท้ายหัวข้อ เช่น "ดูทั้งหมด"
class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool muted;

  const _LinkButton({required this.label, required this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: muted ? AppColors.muted : AppColors.primary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// การ์ดห้องเล็กสองคอลัมน์ (ห้องโปรด / ดูล่าสุด): รหัสอาคาร, รหัสห้อง, ชั้น·ประเภท และสถานะเปิดอยู่
class _MiniRoomGrid extends StatelessWidget {
  final List<Map<String, dynamic>> rooms;
  final String? Function(Map<String, dynamic> room) codeOf;
  final IconData trailingIcon;
  final String? trailingTooltip;
  final void Function(Map<String, dynamic> room)? onTrailing;
  final void Function(Map<String, dynamic> room) onOpen;

  const _MiniRoomGrid({
    required this.rooms,
    required this.codeOf,
    required this.trailingIcon,
    required this.onOpen,
    this.trailingTooltip,
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final room in rooms)
              SizedBox(
                width: width,
                child: Pressable(
                  child: _MiniRoomCard(
                    room: room,
                    buildingCode: codeOf(room),
                    trailingIcon: trailingIcon,
                    trailingTooltip: trailingTooltip,
                    onTrailing: onTrailing == null ? null : () => onTrailing!(room),
                    onOpen: () => onOpen(room),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniRoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final String? buildingCode;
  final IconData trailingIcon;
  final String? trailingTooltip;
  final VoidCallback? onTrailing;
  final VoidCallback onOpen;

  const _MiniRoomCard({
    required this.room,
    required this.buildingCode,
    required this.trailingIcon,
    required this.onOpen,
    this.trailingTooltip,
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final type = room['room_type']?.toString().trim();
    final capacity = room['capacity']?.toString().trim();
    final detail = [
      floorLabel(floorOf(room)),
      if (type != null && type.isNotEmpty) type,
      if ((type == null || type.isEmpty) && capacity != null && capacity.isNotEmpty) '$capacity ที่นั่ง',
    ].join(' • ');
    final open = roomOpenStatus(room);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
          decoration: appCardDecoration(radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        buildingCode ?? room['building_name']?.toString() ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 30,
                    height: 26,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: trailingTooltip,
                      onPressed: onTrailing,
                      icon: Icon(
                        trailingIcon,
                        size: 17,
                        color: onTrailing == null ? AppColors.primary : AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  room['room_code']?.toString() ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ),
              if (open.isKnown) ...[
                const SizedBox(height: 6),
                StatusPill.openStatus(open, short: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildingShortcut extends StatelessWidget {
  final Map<String, dynamic> building;

  const _BuildingShortcut({required this.building});

  @override
  Widget build(BuildContext context) {
    final name = building['name']?.toString() ?? '-';
    final subtitle = [
      '${classroomCountOf(building)} ห้องเรียน',
      '${building['floor_count'] ?? 0} ชั้น',
      if ((building['code']?.toString() ?? '').isNotEmpty) 'รหัส ${building['code']}',
    ].join(' • ');
    final open = buildingOpenStatus(building);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BuildingDetailScreen(building: building)),
        ),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: appCardDecoration(),
          child: Row(
            children: [
              const IconBadge(Icons.apartment_rounded, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(color: AppColors.ink, fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    if (open.isKnown) ...[
                      const SizedBox(height: 6),
                      StatusPill.openStatus(open, short: true),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// ป้ายชวนเปิดแผนที่ท้ายหน้า สำหรับคนที่ยังหาห้องไม่เจอ
class _WayfindingBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _WayfindingBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.tint, AppColors.surface],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'แผนที่ในอาคาร',
                        style: TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ยังหาห้องไม่เจอ?',
                        style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'เปิดแผนที่เพื่อดูตำแหน่งห้องบนแผนผังแต่ละชั้น',
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: Icon(Icons.near_me_rounded, color: AppColors.onPrimary, size: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
