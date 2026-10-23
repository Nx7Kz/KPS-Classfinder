import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'building_detail_screen.dart';
import 'motion.dart';
import 'open_status.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// ประกาศที่ผู้ใช้ควรรู้ สรุปจากข้อมูลจริงในระบบ: วันปิดทำการพิเศษ (ทั้งมหาวิทยาลัย/อาคาร/ห้อง) และห้องที่ปิดปรับปรุง
class Announcement {
  final String id;
  final IconData icon;
  final String title;
  final String detail;

  /// เร่งด่วน = เกิดขึ้นตอนนี้ (เช่น ปิดทำการวันนี้) แสดงเป็นสีส้ม
  final bool urgent;

  /// อาคารที่เกี่ยวข้อง (ถ้ามี) แตะแล้วเปิดหน้าอาคาร
  final Map<String, dynamic>? building;

  const Announcement({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    this.urgent = false,
    this.building,
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

/// รวมประกาศทั้งหมด: วันปิดที่กำลังเกิดขึ้น/มาถึงใน 14 วัน (เรียงตามวัน) แล้วตามด้วยอาคารที่มีห้องปิดปรับปรุง
List<Announcement> buildAnnouncements(List<Map<String, dynamic>> buildings, {DateTime? at}) {
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
      icon: Icons.event_busy_rounded,
      title: active ? 'ปิดทำการวันนี้ • ${_closureScope(closure)}' : 'ปิดทำการ $range • ${_closureScope(closure)}',
      detail: [
        if (active && start != end) 'ถึง ${shortThaiDate(end)}',
        if (reason != null && reason.isNotEmpty) reason,
      ].join(' • '),
      urgent: active,
      building: _buildingById(buildings, closure['building_id']),
    ));
  }

  for (final building in buildings) {
    final count = int.tryParse('${building['maintenance_count']}') ?? 0;
    if (count <= 0) continue;
    items.add(Announcement(
      id: 'maintenance-${building['id']}',
      icon: Icons.build_rounded,
      title: 'ปิดปรับปรุง $count ห้อง • ${building['name'] ?? ''}',
      detail: 'แตะเพื่อดูรายการห้องในอาคาร',
      building: building,
    ));
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

/// หน้ารายการประกาศทั้งหมด (ดึงข้อมูลล่าสุดทุกครั้งที่เปิด ดึงลงเพื่อรีเฟรชได้)
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late Future<List<Announcement>> _future = _load();

  Future<List<Announcement>> _load() async {
    final buildings = await Api.buildings();
    await ClosureStore.refresh();
    return buildAnnouncements(buildings);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'ย้อนกลับ',
                    icon: Icon(Icons.arrow_back_rounded, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text('ประกาศ', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.fill,
                child: FutureBuilder<List<Announcement>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: SkeletonList(count: 3, spacing: 10, itemBuilder: (_) => const Shimmer(child: SkeletonBox(height: 66, radius: 14))),
                      );
                    }
                    if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _reload);
                    final items = snapshot.data ?? const [];
                    if (items.isEmpty) {
                      return const StateView(
                        icon: Icons.notifications_none_rounded,
                        title: 'ไม่มีประกาศ',
                        message: 'ตอนนี้ไม่มีวันปิดทำการพิเศษหรือห้องที่ปิดปรับปรุง',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          for (final (i, item) in items.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FadeSlideIn(
                                index: i,
                                child: AnnouncementTile(
                                  item: item,
                                  onTap: item.building == null ? null : () => openAnnouncementTarget(context, item),
                                ),
                              ),
                            ),
                        ],
                      ),
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
}
