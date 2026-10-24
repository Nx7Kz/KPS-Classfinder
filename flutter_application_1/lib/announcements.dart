import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'building_detail_screen.dart';
import 'motion.dart';
import 'open_status.dart';
import 'report_sheet.dart';
import 'room_utils.dart';
import 'skeleton.dart';
import 'widgets.dart';

enum AnnouncementKind { closure, maintenance, suspended }

/// ประกาศที่ผู้ใช้ควรรู้ สรุปจากข้อมูลจริงในระบบ: วันปิดทำการพิเศษ (ทั้งมหาวิทยาลัย/อาคาร/ห้อง) ห้องที่ปิดปรับปรุง และห้องที่งดใช้งาน
class Announcement {
  final String id;
  final AnnouncementKind kind;
  final IconData icon;
  final String title;
  final String detail;

  /// เร่งด่วน = เกิดขึ้นตอนนี้ (เช่น ปิดทำการวันนี้) แสดงเป็นสีส้ม
  final bool urgent;

  /// อาคารที่เกี่ยวข้อง (ถ้ามี) แตะแล้วเปิดหน้าอาคาร
  final Map<String, dynamic>? building;

  /// ขอบเขตของประกาศ เช่น "อาคารเรียน 80 ปี" หรือ "ทั้งมหาวิทยาลัย"
  final String scope;

  /// ป้ายสถานะ เช่น "ปิดทำการ" / "ปิดปรับปรุง"
  final String statusLabel;

  /// ข้อความเสริมในแถวป้าย เช่น รายชื่อห้องที่ปิดปรับปรุง
  final String infoLabel;

  /// วันที่ของประกาศ เช่น "26 ต.ค. – 27 ต.ค." (ประกาศห้องปิดปรับปรุงไม่มีวันที่)
  final String dateLabel;

  const Announcement({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    this.kind = AnnouncementKind.closure,
    this.urgent = false,
    this.building,
    this.scope = '',
    this.statusLabel = '',
    this.infoLabel = '',
    this.dateLabel = '',
  });
}

const _thaiMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

/// "2026-10-26" -> "26 ต.ค."
String shortThaiDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return value;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null || month < 1 || month > 12) return value;
  return '$day ${_thaiMonths[month - 1]}';
}

String _closureScope(Map<String, dynamic> closure) {
  final room = closure['room_code']?.toString();
  final building = closure['building_name']?.toString();
  if (room != null && room.isNotEmpty) return 'ห้อง $room${building == null ? '' : ' ($building)'}';
  if (building != null && building.isNotEmpty) return building;
  return 'ทั้งมหาวิทยาลัย';
}

Map<String, dynamic>? _buildingById(List<Map<String, dynamic>> buildings, Object? id) {
  if (id == null) return null;
  for (final building in buildings) {
    if (building['id'].toString() == id.toString()) return building;
  }
  return null;
}

/// "ห้อง A, B, C +2" (แสดงไม่เกิน 3 ห้อง)
String _roomCodesLabel(List<Map<String, dynamic>> rooms) {
  final codes = [for (final room in rooms) room['room_code'].toString()];
  if (codes.isEmpty) return '';
  final shown = codes.take(3).join(', ');
  final more = codes.length > 3 ? ' +${codes.length - 3}' : '';
  return 'ห้อง $shown$more';
}

/// สาเหตุของห้องที่งดใช้งาน: ถ้าทุกห้องใช้สาเหตุเดียวกันแสดงข้อความนั้น ถ้าต่างกันแสดงให้แตะดูรายการ
String _suspendedDetail(List<Map<String, dynamic>> rooms) {
  final reasons = {for (final room in rooms) ?statusReasonOf(room)};
  if (reasons.length == 1 && rooms.every((room) => statusReasonOf(room) != null)) return reasons.first;
  return reasons.isEmpty ? 'แตะเพื่อดูรายการห้องในอาคาร' : 'หลายสาเหตุ • แตะเพื่อดูรายการห้องในอาคาร';
}

/// รวมประกาศทั้งหมด: วันปิดที่กำลังเกิดขึ้น/มาถึงใน 14 วัน (เรียงตามวัน) แล้วตามด้วยอาคารที่มีห้องปิดปรับปรุง
/// [maintenanceRooms] / [suspendedRooms] = ห้องที่ปิดปรับปรุง/งดใช้งานของแต่ละอาคาร (key = รหัสอาคาร)
/// ใช้แสดงรหัสห้องและสาเหตุในการ์ด ถ้าไม่ส่งก็แสดงแค่จำนวนห้อง
List<Announcement> buildAnnouncements(
  List<Map<String, dynamic>> buildings, {
  DateTime? at,
  Map<String, List<Map<String, dynamic>>> maintenanceRooms = const {},
  Map<String, List<Map<String, dynamic>>> suspendedRooms = const {},
}) {
  final today = todayKeyBangkok(at: at);
  final items = <Announcement>[];

  for (final closure in upcomingClosures(at: at)) {
    final start = closure['start_date']?.toString() ?? '';
    final end = closure['end_date']?.toString() ?? '';
    final active = today.compareTo(start) >= 0 && today.compareTo(end) <= 0;
    final range = start == end ? shortThaiDate(start) : '${shortThaiDate(start)} – ${shortThaiDate(end)}';
    final reason = closure['reason']?.toString();
    items.add(Announcement(
      id: 'closure-${closure['id']}',
      kind: AnnouncementKind.closure,
      icon: Icons.event_busy_rounded,
      title: active ? 'ปิดทำการวันนี้ • ${_closureScope(closure)}' : 'ปิดทำการ $range • ${_closureScope(closure)}',
      detail: [
        if (active && start != end) 'ถึง ${shortThaiDate(end)}',
        if (reason != null && reason.isNotEmpty) reason,
      ].join(' • '),
      urgent: active,
      building: _buildingById(buildings, closure['building_id']),
      scope: _closureScope(closure),
      statusLabel: active ? 'กำลังปิดทำการ' : 'ปิดทำการ',
      dateLabel: range,
    ));
  }

  for (final building in buildings) {
    final count = int.tryParse('${building['maintenance_count']}') ?? 0;
    if (count > 0) {
      items.add(Announcement(
        id: 'maintenance-${building['id']}',
        kind: AnnouncementKind.maintenance,
        icon: Icons.build_rounded,
        title: 'ปิดปรับปรุง $count ห้อง • ${building['name'] ?? ''}',
        detail: 'แตะเพื่อดูรายการห้องในอาคาร',
        building: building,
        scope: building['name']?.toString() ?? '',
        statusLabel: 'ปิดปรับปรุง',
        infoLabel: _roomCodesLabel(maintenanceRooms[building['id'].toString()] ?? const []),
      ));
    }

    final suspended = int.tryParse('${building['suspended_count']}') ?? 0;
    if (suspended > 0) {
      final suspendedList = suspendedRooms[building['id'].toString()] ?? const <Map<String, dynamic>>[];
      items.add(Announcement(
        id: 'suspended-${building['id']}',
        kind: AnnouncementKind.suspended,
        icon: Icons.block_rounded,
        title: 'งดใช้งาน $suspended ห้อง • ${building['name'] ?? ''}',
        detail: suspendedList.isEmpty ? 'แตะเพื่อดูรายการห้องในอาคาร' : _suspendedDetail(suspendedList),
        building: building,
        scope: building['name']?.toString() ?? '',
        statusLabel: 'งดใช้งาน',
        infoLabel: _roomCodesLabel(suspendedList),
      ));
    }
  }
  return items;
}

class AnnouncementTile extends StatelessWidget {
  final Announcement item;
  final VoidCallback? onTap;

  const AnnouncementTile({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = item.urgent ? AppColors.warning : AppColors.primary;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: appCardDecoration(radius: 14, color: item.urgent ? AppColors.warningTint : null),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: item.urgent ? AppColors.surface.withValues(alpha: 0.7) : AppColors.tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: TextStyle(color: AppColors.ink, fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.25)),
                    if (item.detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.detail, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3)),
                    ],
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

void openAnnouncementTarget(BuildContext context, Announcement item) {
  final building = item.building;
  if (building == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BuildingDetailScreen(building: building)));
}

Future<void> openAnnouncements(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen()));
}

class _AnnouncementData {
  final List<Announcement> items;
  final DateTime loadedAt;

  const _AnnouncementData(this.items, this.loadedAt);
}

/// หน้ารายการประกาศทั้งหมด (ดึงข้อมูลล่าสุดทุกครั้งที่เปิด ดึงลงเพื่อรีเฟรชได้)
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late Future<_AnnouncementData> _future = _load();
  AnnouncementKind? _filter;

  Future<_AnnouncementData> _load() async {
    final buildings = await Api.buildings();
    await ClosureStore.refresh();

    // รายชื่อห้องที่ปิดปรับปรุงของแต่ละอาคาร (ดึงไม่สำเร็จก็แค่ไม่แสดงรายชื่อห้อง)
    final maintenanceRooms = <String, List<Map<String, dynamic>>>{};
    final suspendedRooms = <String, List<Map<String, dynamic>>>{};
    for (final building in buildings) {
      final count = (int.tryParse('${building['maintenance_count']}') ?? 0) + (int.tryParse('${building['suspended_count']}') ?? 0);
      if (count <= 0) continue;
      try {
        final rooms = await Api.roomsInBuilding(building['name'].toString());
        maintenanceRooms[building['id'].toString()] = [for (final room in rooms) if (isMaintenance(room)) room];
        suspendedRooms[building['id'].toString()] = [for (final room in rooms) if (isSuspended(room)) room];
      } catch (_) {}
    }
    return _AnnouncementData(
      buildAnnouncements(buildings, maintenanceRooms: maintenanceRooms, suspendedRooms: suspendedRooms),
      DateTime.now(),
    );
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // แสดงผลในหน้าจออยู่แล้ว
    }
  }

  String _timeLabel(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return 'อัปเดตล่าสุด วันนี้ $hh:$mm น.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
              decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.line))),
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
                        Text('ประกาศ', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                        Text('อัปเดตสถานะอาคารและห้องเรียน', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.fill,
                child: FutureBuilder<_AnnouncementData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: SkeletonList(count: 3, spacing: 10, itemBuilder: (_) => const Shimmer(child: SkeletonBox(height: 96, radius: 18))),
                      );
                    }
                    if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _reload);
                    final data = snapshot.data!;
                    if (data.items.isEmpty) {
                      return const StateView(
                        icon: Icons.notifications_none_rounded,
                        title: 'ไม่มีประกาศ',
                        message: 'ตอนนี้ไม่มีวันปิดทำการพิเศษ ห้องที่ปิดปรับปรุง หรือห้องที่งดใช้งาน',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: _content(data),
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

  Widget _content(_AnnouncementData data) {
    final all = data.items;
    final shown = _filter == null ? all : all.where((item) => item.kind == _filter).toList();
    final urgent = shown.where((item) => item.urgent).toList();
    final rest = shown.where((item) => !item.urgent).toList();

    int count(AnnouncementKind kind) => all.where((item) => item.kind == kind).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _FilterPill(label: 'ทั้งหมด (${all.length})', selected: _filter == null, onTap: () => setState(() => _filter = null)),
              const SizedBox(width: 8),
              _FilterPill(
                label: 'ปิดทำการ (${count(AnnouncementKind.closure)})',
                selected: _filter == AnnouncementKind.closure,
                onTap: () => setState(() => _filter = AnnouncementKind.closure),
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: 'ปิดปรับปรุง (${count(AnnouncementKind.maintenance)})',
                selected: _filter == AnnouncementKind.maintenance,
                onTap: () => setState(() => _filter = AnnouncementKind.maintenance),
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: 'งดใช้งาน (${count(AnnouncementKind.suspended)})',
                selected: _filter == AnnouncementKind.suspended,
                onTap: () => setState(() => _filter = AnnouncementKind.suspended),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final item in urgent)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _UrgentBanner(item: item, onTap: item.building == null ? null : () => openAnnouncementTarget(context, item)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('รายการประกาศล่าสุด', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(_timeLabel(data.loadedAt), style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ],
          ),
        ),
        if (rest.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('ไม่มีประกาศอื่นในหมวดนี้', style: TextStyle(color: AppColors.muted, fontSize: 13))),
          ),
        for (final (i, item) in rest.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeSlideIn(
              index: i,
              child: _AnnouncementCard(item: item, onTap: item.building == null ? null : () => openAnnouncementTarget(context, item)),
            ),
          ),
        const SizedBox(height: 4),
        _ReportStrip(onTap: () => showReportSheet(context)),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : AppColors.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.onPrimary : AppColors.muted,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// ประกาศที่กำลังเกิดขึ้นตอนนี้ (เช่น ปิดทำการวันนี้) เด่นอยู่ด้านบนของหน้า
class _UrgentBanner extends StatelessWidget {
  final Announcement item;
  final VoidCallback? onTap;

  const _UrgentBanner({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.warningTint, AppColors.surface],
            ),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text('กำลังเกิดขึ้นตอนนี้', style: TextStyle(color: AppColors.surface, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.push_pin_rounded, size: 19, color: AppColors.warning),
                ],
              ),
              const SizedBox(height: 10),
              Text(item.title, style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800, height: 1.3)),
              if (item.detail.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(item.detail, style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45)),
              ],
              if (item.building != null) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: AppColors.warning.withValues(alpha: 0.18)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item.scope, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.warning, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    Text('ดูอาคาร', style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w800)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.warning),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement item;
  final VoidCallback? onTap;

  const _AnnouncementCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final closure = item.kind == AnnouncementKind.closure;
    final suspended = item.kind == AnnouncementKind.suspended;
    final badgeColor = suspended ? AppColors.dangerTint : (closure ? AppColors.warningTint : AppColors.tint);
    final iconColor = suspended ? AppColors.danger : (closure ? AppColors.warning : AppColors.primary);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: appCardDecoration(radius: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(16)),
                child: Icon(item.icon, size: 24, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.ink, fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.3)),
                        ),
                        if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
                      ],
                    ),
                    if (item.detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(item.detail, style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (item.statusLabel.isNotEmpty) _Chip(label: item.statusLabel, background: closure ? AppColors.warningTint : AppColors.dangerTint, color: closure ? AppColors.warning : AppColors.danger, bold: true),
                              if (item.infoLabel.isNotEmpty) _Chip(label: item.infoLabel, background: AppColors.fill, color: AppColors.muted),
                            ],
                          ),
                        ),
                        if (item.dateLabel.isNotEmpty) Text(item.dateLabel, style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
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

class _Chip extends StatelessWidget {
  final String label;
  final Color background;
  final Color color;
  final bool bold;

  const _Chip({required this.label, required this.background, required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
    );
  }
}

/// ท้ายหน้า ชวนแจ้งผู้ดูแลเมื่อข้อมูลหรืออุปกรณ์ไม่ตรง
class _ReportStrip extends StatelessWidget {
  final VoidCallback onTap;

  const _ReportStrip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Icon(Icons.support_agent_rounded, size: 24, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('พบข้อมูลหรืออุปกรณ์ไม่ถูกต้อง?', style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                Text('แจ้งผู้ดูแลให้ตรวจสอบได้ทันที', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.line),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('แจ้งปัญหา', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
