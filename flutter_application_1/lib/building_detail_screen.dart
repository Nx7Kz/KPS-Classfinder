import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'motion.dart';
import 'open_status.dart';
import 'panorama_screen.dart';
import 'room_detail_screen.dart';
import 'room_list_screen.dart';
import 'report_sheet.dart';
import 'room_utils.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// หน้ารายละเอียดอาคาร: รูปปก ข้อมูล/เวลาทำการ ทางลัดไปแผนผังและภาพ 360° รายการห้องแยกตามชั้น
/// และสิ่งอำนวยความสะดวกที่สรุปจากข้อมูลห้องจริงของอาคาร (ลิฟต์ ห้องน้ำ Wi-Fi ที่นั่ง ฯลฯ)
class BuildingDetailScreen extends StatefulWidget {
  /// แถวอาคารจาก /api/buildings (มี code, name, ที่ตั้ง, เวลาทำการ, จำนวนต่าง ๆ)
  final Map<String, dynamic> building;

  const BuildingDetailScreen({super.key, required this.building});

  @override
  State<BuildingDetailScreen> createState() => _BuildingDetailScreenState();
}

class _BuildingDetailScreenState extends State<BuildingDetailScreen> {
  late Future<List<Map<String, dynamic>>> _roomsFuture;
  String? _floor;
  bool _showWeek = false;

  String get _name => widget.building['name']?.toString() ?? '-';
  String get _code => widget.building['code']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _roomsFuture = Api.roomsInBuilding(_name);
  }

  void _reload() => setState(() => _roomsFuture = Api.roomsInBuilding(_name));

  Future<void> _share(BuildContext buttonContext) async {
    final text = [
      _name,
      if (_code.isNotEmpty) 'รหัสอาคาร $_code',
      '${widget.building['floor_count'] ?? 0} ชั้น • ${widget.building['room_count'] ?? 0} ห้อง',
      '',
      'ดูห้องและแผนที่ในแอป KPS ClassFinder',
    ].join('\n');
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: '$_name · KPS ClassFinder', sharePositionOrigin: origin),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // แชร์ไม่ได้ ใช้การคัดลอกแทน
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnack(context, 'คัดลอกข้อมูลอาคารแล้ว นำไปวางในแชทได้เลย');
  }

  void _openMap([String? floor]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MapScreen(initialBuilding: _name, initialFloor: floor)),
    );
  }

  void _openRoomList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoomListScreen(buildingName: _name, buildingCode: _code)),
    );
  }

  /// รายการห้องที่มีภาพ 360° ของอาคาร แตะเพื่อเปิดภาพ
  void _open360(List<Map<String, dynamic>> rooms) {
    final shown = rooms.where(hasPanorama).toList();
    if (shown.isEmpty) {
      showAppSnack(context, 'อาคารนี้ยังไม่มีภาพ 360°');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'ภาพ 360° · $_name (${shown.length} ห้อง)',
              style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final room in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RoomTile(
                  room: room,
                  showBuilding: false,
                  icon: Icons.threesixty_rounded,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    openPanorama(context, room);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              title: _name,
              subtitle: [if (_code.isNotEmpty) 'รหัส $_code', 'วิทยาเขตกำแพงแสน'].join(' • '),
              onShare: _share,
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.fill,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _roomsFuture,
                  builder: (context, snapshot) {
                    final loading = snapshot.connectionState != ConnectionState.done;
                    final rooms = snapshot.data ?? const <Map<String, dynamic>>[];
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                      children: [
                        _Hero(building: widget.building),
                        const SizedBox(height: 12),
                        _QuickBadges(building: widget.building, rooms: rooms),
                        const SizedBox(height: 16),
                        _InfoCard(
                          building: widget.building,
                          rooms: rooms,
                          showWeek: _showWeek,
                          onToggleWeek: () => setState(() => _showWeek = !_showWeek),
                        ),
                        const SizedBox(height: 14),
                        _Actions(
                          panoramaRooms: rooms.where(hasPanorama).length,
                          loading: loading,
                          onMap: () => _openMap(),
                          on360: () => _open360(rooms),
                        ),
                        if (loading) ...[
                          const SizedBox(height: 20),
                          const Shimmer(child: SkeletonBox(height: 52, radius: 14)),
                          const SizedBox(height: 10),
                          const Shimmer(child: SkeletonBox(height: 70, radius: 16)),
                          const SizedBox(height: 10),
                          const Shimmer(child: SkeletonBox(height: 70, radius: 16)),
                        ] else if (snapshot.hasError)
                          SizedBox(height: 240, child: StateView.error(snapshot.error!, onRetry: _reload))
                        else if (rooms.isEmpty)
                          const SizedBox(
                            height: 220,
                            child: StateView(
                              icon: Icons.meeting_room_outlined,
                              title: 'ยังไม่มีข้อมูลห้องเรียน',
                              message: 'ยังไม่มีห้องเรียนในอาคารนี้ในระบบ',
                            ),
                          )
                        else ...[
                          ..._buildFloors(rooms),
                          ..._buildFacilities(rooms),
                        ],
                        const SizedBox(height: 24),
                        ReportLinkCard(
                          title: 'ข้อมูลอาคารนี้ไม่ตรง?',
                          onTap: () => showReportSheet(context, building: widget.building),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFloors(List<Map<String, dynamic>> rooms) {
    final floors = sortFloors(rooms.map(floorOf));
    final floor = floors.contains(_floor) ? _floor! : floors.first;
    final onFloor = rooms.where((room) => floorOf(room) == floor).toList()
      ..sort((a, b) => (a['room_code']?.toString() ?? '').compareTo(b['room_code']?.toString() ?? ''));
    final counts = <String, int>{};
    for (final room in rooms) {
      counts[floorOf(room)] = (counts[floorOf(room)] ?? 0) + 1;
    }

    return [
      const SizedBox(height: 22),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ชั้นเรียนในอาคาร', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('เลือกชั้นเพื่อดูรายการห้อง', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(999)),
            child: Text('รวม ${rooms.length} ห้อง', style: TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (floors.length > 1)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              for (final f in floors)
                Expanded(
                  child: _FloorTab(
                    label: floorLabel(f),
                    count: counts[f] ?? 0,
                    active: f == floor,
                    onTap: () => setState(() => _floor = f),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      for (final (i, room) in onFloor.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RoomTile(
            room: room,
            entranceIndex: i,
            showBuilding: false,
            onTap: () => openRoom(context, room),
          ),
        ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.surface),
              onPressed: () => _openMap(floor == '-' ? null : floor),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('ผังชั้นนี้', maxLines: 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.surface),
              onPressed: _openRoomList,
              icon: const Icon(Icons.manage_search_rounded, size: 19),
              label: const Text('ค้นหาห้อง', maxLines: 1),
            ),
          ),
        ],
      ),
    ];
  }

  /// สรุปสิ่งอำนวยความสะดวกจากข้อมูลห้องจริง แสดงเฉพาะรายการที่มีข้อมูล
  List<Widget> _buildFacilities(List<Map<String, dynamic>> rooms) {
    int count(String word) => rooms.where((r) => '${r['room_type'] ?? ''} ${r['room_code'] ?? ''}'.contains(word)).length;
    int sum(String key) => rooms.fold<int>(0, (total, r) => total + (int.tryParse('${amenitiesOf(r)[key]}') ?? 0));

    final elevators = count('ลิฟต์');
    final restrooms = count('ห้องน้ำ');
    final outlets = sum('outlets');
    final ac = sum('ac');
    final wifi = {
      for (final r in rooms)
        if ((amenitiesOf(r)['wifi']?.toString() ?? '').trim().isNotEmpty) amenitiesOf(r)['wifi'].toString().trim(),
    }.toList();

    final items = <(IconData, String)>[
      if (elevators > 0) (Icons.elevator_rounded, 'ลิฟต์ $elevators จุด'),
      if (restrooms > 0) (Icons.wc_rounded, 'ห้องน้ำ $restrooms จุด'),
      if (wifi.isNotEmpty) (Icons.wifi_rounded, 'Wi-Fi ${wifi.take(2).join(', ')}'),
      if (outlets > 0) (Icons.power_rounded, 'ปลั๊กไฟ $outlets จุด'),
      if (ac > 0) (Icons.ac_unit_rounded, 'เครื่องปรับอากาศ $ac เครื่อง'),
    ];
    if (items.isEmpty) return const [];

    return [
      const SizedBox(height: 24),
      Text('สิ่งอำนวยความสะดวก', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text('สรุปจากข้อมูลห้องในอาคารนี้', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (icon, label) in items)
                Container(
                  width: width,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.tint.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: AppColors.primary),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final Future<void> Function(BuildContext buttonContext) onShare;

  const _Header({required this.title, required this.subtitle, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
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
                  style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.2),
                ),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'แชร์อาคารนี้',
              icon: Icon(Icons.share_outlined, size: 21, color: AppColors.muted),
              onPressed: () => onShare(buttonContext),
            ),
          ),
        ],
      ),
    );
  }
}

/// รูปปกเต็มความกว้าง + ป้ายรหัสอาคารมุมซ้ายบน + ที่ตั้ง/สถานะเปิดปิดด้านล่าง (ไล่เฉดดำให้อ่านง่าย)
class _Hero extends StatelessWidget {
  final Map<String, dynamic> building;

  const _Hero({required this.building});

  @override
  Widget build(BuildContext context) {
    final cover = building['cover_image']?.toString();
    final plan = building['floor_plan_image']?.toString();
    final hasCover = cover != null && cover.isNotEmpty;
    final hasPlan = plan != null && plan.isNotEmpty;
    final code = building['code']?.toString() ?? '';
    final location = building['location']?.toString().trim() ?? '';
    final status = buildingOpenStatus(building);

    Widget image;
    if (hasCover || hasPlan) {
      image = Container(
        color: hasCover ? AppColors.fill : const Color(0xFFF7F8F6),
        padding: hasCover ? EdgeInsets.zero : const EdgeInsets.all(12),
        child: Image.network(
          Api.assetUrl(hasCover ? cover : plan!),
          fit: hasCover ? BoxFit.cover : BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null ? child : const Shimmer(child: SkeletonBox(radius: 0)),
          errorBuilder: (_, _, _) => Center(child: Icon(Icons.apartment_rounded, color: AppColors.muted, size: 48)),
        ),
      );
    } else {
      image = Container(color: AppColors.tint, child: Center(child: Icon(Icons.apartment_rounded, color: AppColors.primary, size: 56)));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (hasCover)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
            if (code.isNotEmpty)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(code, style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            if (hasCover)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location.isEmpty ? 'วิทยาเขตกำแพงแสน' : location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (status.isKnown)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: (status.state == OpenState.open ? AppColors.primaryDark : Colors.black).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(status.shortLabel, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ป้ายสรุปแนวนอน: ชั้น/ห้อง/ภาพ 360°/ปิดปรับปรุง/ลิฟต์ (นับจากข้อมูลจริง)
class _QuickBadges extends StatelessWidget {
  final Map<String, dynamic> building;
  final List<Map<String, dynamic>> rooms;

  const _QuickBadges({required this.building, required this.rooms});

  @override
  Widget build(BuildContext context) {
    final roomCount = int.tryParse('${building['room_count']}') ?? rooms.length;
    final panoRooms = rooms.isNotEmpty ? rooms.where(hasPanorama).length : (int.tryParse('${building['panorama_room_count']}') ?? 0);
    final maintenance = int.tryParse('${building['maintenance_count']}') ?? 0;
    final hasElevator = rooms.any((r) => '${r['room_type'] ?? ''} ${r['room_code'] ?? ''}'.contains('ลิฟต์'));

    final badges = <(IconData, String, bool)>[
      (Icons.layers_outlined, '${building['floor_count'] ?? 0} ชั้น', false),
      (Icons.meeting_room_outlined, '$roomCount ห้อง', false),
      if (panoRooms > 0) (Icons.threesixty_rounded, panoRooms >= roomCount ? 'มีภาพ 360° ครบทุกห้อง' : 'ภาพ 360° $panoRooms ห้อง', false),
      if (hasElevator) (Icons.elevator_outlined, 'มีลิฟต์', false),
      if (maintenance > 0) (Icons.build_rounded, 'ปิดปรับปรุง $maintenance ห้อง', true),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: badges.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final (icon, label, warning) = badges[index];
          final color = warning ? AppColors.warning : AppColors.primary;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: warning ? AppColors.warningTint : AppColors.tint,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// การ์ด "ข้อมูลและเวลาทำการ": ที่ตั้ง คำอธิบาย เวลาทำการวันนี้ (กดดูทั้งสัปดาห์ได้) และที่นั่งรวม
class _InfoCard extends StatelessWidget {
  final Map<String, dynamic> building;
  final List<Map<String, dynamic>> rooms;
  final bool showWeek;
  final VoidCallback onToggleWeek;

  const _InfoCard({required this.building, required this.rooms, required this.showWeek, required this.onToggleWeek});

  @override
  Widget build(BuildContext context) {
    final location = building['location']?.toString().trim() ?? '';
    final description = building['description']?.toString().trim() ?? '';
    final hoursRaw = building['open_hours'];
    final hours = hoursRaw is Map ? Map<String, dynamic>.from(hoursRaw) : null;
    final seats = rooms.fold<int>(0, (total, r) => total + (int.tryParse('${r['capacity']}') ?? 0));

    String hoursText = 'ยังไม่ระบุ';
    if (hours != null) {
      final today = weeklyHoursRows(hours).firstWhere((row) => row.isToday);
      hoursText = today.isClosed ? 'วันนี้ปิดทำการ' : today.text;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: appCardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('ข้อมูลและเวลาทำการ', style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          if (location.isNotEmpty) ...[
            _InfoLine(icon: Icons.near_me_outlined, label: 'ที่ตั้งอาคาร', value: location),
            const SizedBox(height: 12),
          ],
          if (description.isNotEmpty) ...[
            _InfoLine(icon: Icons.notes_rounded, label: 'รายละเอียด', value: description),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _InfoLine(icon: Icons.schedule_rounded, label: 'เวลาทำการวันนี้', value: hoursText, bold: true)),
              if (seats > 0) ...[
                const SizedBox(width: 12),
                Expanded(child: _InfoLine(icon: Icons.groups_rounded, label: 'ที่นั่งรวม', value: '$seats ที่นั่ง', bold: true)),
              ],
            ],
          ),
          if (hours != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)),
                onPressed: onToggleWeek,
                icon: Icon(showWeek ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                label: Text(showWeek ? 'ซ่อนเวลาทั้งสัปดาห์' : 'ดูเวลาทั้งสัปดาห์', style: const TextStyle(fontSize: 13)),
              ),
            ),
            if (showWeek) HoursCard(rows: weeklyHoursRows(hours)),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool bold;

  const _InfoLine({required this.icon, required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: AppColors.tint, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(color: AppColors.ink, fontSize: bold ? 14.5 : 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ปุ่มทางลัดใหญ่สองปุ่ม: เปิดผังแผนที่ชั้น (เขียวเต็ม) / ดูภาพ 360° (ขาว)
class _Actions extends StatelessWidget {
  final int panoramaRooms;
  final bool loading;
  final VoidCallback onMap;
  final VoidCallback on360;

  const _Actions({required this.panoramaRooms, required this.loading, required this.onMap, required this.on360});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            filled: true,
            icon: Icons.map_rounded,
            title: 'เปิดผังแผนที่ชั้น',
            subtitle: 'แตะหมุดเพื่อดูห้อง',
            onTap: onMap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            filled: false,
            icon: Icons.threesixty_rounded,
            title: 'ดูภาพ 360°',
            subtitle: loading ? 'กำลังโหลด...' : (panoramaRooms == 0 ? 'ยังไม่มีภาพ' : '$panoramaRooms ห้องมีภาพ'),
            onTap: loading ? null : on360,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final bool filled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionCard({required this.filled, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onPrimary : AppColors.ink;
    return Pressable(
      child: Material(
        color: filled ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: filled ? null : appCardDecoration(radius: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: filled ? AppColors.onPrimary.withValues(alpha: 0.16) : AppColors.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 21, color: filled ? AppColors.onPrimary : AppColors.primary),
                ),
                const SizedBox(height: 10),
                Text(title, style: TextStyle(color: fg, fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: filled ? AppColors.onPrimary.withValues(alpha: 0.8) : AppColors.muted, fontSize: 11.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// แท็บเลือกชั้นแบบแคปซูลในกล่องเดียว มีเลขจำนวนห้องเล็ก ๆ ท้ายชื่อชั้น
class _FloorTab extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _FloorTab({required this.label, required this.count, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.onPrimary : AppColors.muted;
    return Material(
      color: active ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () {
          if (!active) Haptics.select();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: active ? FontWeight.w800 : FontWeight.w600),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active ? AppColors.onPrimary.withValues(alpha: 0.2) : AppColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
