import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'motion.dart';
import 'open_status.dart';
import 'panorama_screen.dart';
import 'report_sheet.dart';
import 'room_store.dart';
import 'room_utils.dart';
import 'skeleton.dart';
import 'tour_screen.dart';
import 'widgets.dart';

/// เปิดหน้ารายละเอียดห้อง (ใช้ร่วมกันทุกหน้า)
Future<void> openRoom(BuildContext context, Map<String, dynamic> room) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
  );
}

class RoomDetailScreen extends StatefulWidget {
  final Map<String, dynamic> room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  bool _isFavorite = false;
  bool _isLoadingFavorite = true;
  List<Map<String, dynamic>> _panoramas = const [];
  bool _panoramasLoaded = false;

  Map<String, dynamic> get room => widget.room;

  @override
  void initState() {
    super.initState();
    RoomStore.addRecent(room);
    _loadFavoriteState();
    _loadPanoramas();
  }

  Future<void> _loadFavoriteState() async {
    final isFavorite = await RoomStore.isFavorite(room);
    if (!mounted) return;
    setState(() {
      _isFavorite = isFavorite;
      _isLoadingFavorite = false;
    });
  }

  /// ไม่มีภาพ 360° หรือโหลดไม่ได้ก็แค่ไม่แสดงปุ่ม ไม่รบกวนหน้ารายละเอียดหลัก
  Future<void> _loadPanoramas() async {
    final id = room['id'];
    if (id == null) return;
    try {
      final panoramas = await Api.panoramas(id);
      if (!mounted) return;
      setState(() => _panoramas = panoramas);
    } catch (_) {
      // ไม่มีก็ไม่แสดง
    } finally {
      if (mounted) setState(() => _panoramasLoaded = true);
    }
  }

  /// การ์ดตัวอย่างภาพ 360°: แสดงเฉพาะห้องที่มีภาพ ระหว่างโหลดใช้โครงร่างขนาดเท่าการ์ด
  /// (รู้ล่วงหน้าจาก panorama_count ที่มากับข้อมูลห้อง จึงไม่มีการ์ดว่างกะพริบในห้องที่ไม่มีภาพ)
  List<Widget> _buildPanoramaSection() {
    if (_panoramasLoaded ? _panoramas.isEmpty : !hasPanorama(room)) return const [];
    return [
      const SizedBox(height: 22),
      _SectionHeader(
        icon: Icons.threesixty_rounded,
        title: 'ภาพพาโนรามา 360°',
        trailing: _panoramasLoaded && _panoramas.isNotEmpty ? _SoftPill('${_panoramas.length} มุมมอง') : null,
      ),
      const SizedBox(height: 10),
      if (!_panoramasLoaded)
        const Shimmer(child: SkeletonBox(height: 208, radius: 18))
      else
        _PanoramaPreview(panoramas: _panoramas, onOpen: _openPanorama),
    ];
  }

  Future<void> _toggleFavorite() async {
    Haptics.tap();
    final nowFavorite = await RoomStore.toggleFavorite(room);
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
    showAppSnack(context, nowFavorite ? 'บันทึกเป็นห้องโปรดแล้ว' : 'นำออกจากห้องโปรดแล้ว');
  }

  /// ข้อความที่แชร์: รหัสห้อง อาคาร ชั้น ประเภท/ความจุ (ถ้ามี) และชื่อแอป
  String _shareText() {
    final lines = [
      '${room['room_code'] ?? '-'}',
      '${room['building_name'] ?? '-'} · ${floorLabel(floorOf(room))}',
      ?roomSummary(room),
      if (isMaintenance(room)) '(ปิดปรับปรุงอยู่ในขณะนี้)',
      if (isSuspended(room)) '(งดใช้งานอยู่ในขณะนี้${statusReasonOf(room) == null ? '' : ': ${statusReasonOf(room)}'})',
      '',
      'ดูตำแหน่งบนแผนที่ได้ในแอป KPS ClassFinder',
    ];
    return lines.join('\n');
  }

  /// เปิดเมนูแชร์ของเครื่อง (LINE, Messenger ฯลฯ) ถ้าเครื่อง/เบราว์เซอร์แชร์ไม่ได้ จะคัดลอกข้อความให้แทน
  Future<void> _share(BuildContext buttonContext) async {
    final text = _shareText();
    // iPad ต้องรู้ตำแหน่งปุ่มเพื่อวางป๊อปอัปแชร์
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: '${room['room_code'] ?? ''} · KPS ClassFinder', sharePositionOrigin: origin),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // แชร์ไม่ได้ ใช้การคัดลอกแทน
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnack(context, 'คัดลอกข้อมูลห้องแล้ว นำไปวางในแชทได้เลย');
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          initialBuilding: room['building_name']?.toString(),
          initialFloor: floorOf(room),
          focusRoom: room,
        ),
      ),
    );
  }

  void _openPanorama() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PanoramaScreen(room: room, panoramas: _panoramas)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomCode = room['room_code']?.toString() ?? '-';
    final buildingName = room['building_name']?.toString() ?? '-';
    final floor = floorOf(room);
    final roomType = room['room_type']?.toString();
    final capacity = room['capacity']?.toString();
    final amenities = amenitiesOf(room);
    final openStatus = roomOpenStatus(room);
    final hours = effectiveHours(room);
    final facilities = <(IconData, String)>[
      if (amenities['seats'] != null) (Icons.event_seat_rounded, '${amenities['seats']} ที่นั่ง'),
      if (amenities['outlets'] != null) (Icons.power_rounded, '${amenities['outlets']} จุดปลั๊กไฟ'),
      if (amenities['ac'] != null) (Icons.ac_unit_rounded, '${amenities['ac']} เครื่องปรับอากาศ'),
      if ((amenities['wifi']?.toString() ?? '').isNotEmpty) (Icons.wifi_rounded, '${amenities['wifi']}'),
    ];
    final hasRoomType = roomType != null && roomType.isNotEmpty;
    final hasCapacity = capacity != null && capacity.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DetailHeader(
              isFavorite: _isFavorite,
              loadingFavorite: _isLoadingFavorite,
              onFavorite: _toggleFavorite,
              onShare: _share,
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.fill,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Text(
                      roomCode,
                      style: TextStyle(color: AppColors.ink, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.apartment_rounded, size: 16, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(buildingName, style: TextStyle(color: AppColors.muted, fontSize: 15))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusPill(label: floorLabel(floor), icon: Icons.layers_rounded),
                        if (hasRoomType) StatusPill(label: roomType, icon: Icons.category_rounded),
                        if (isMaintenance(room))
                          const StatusPill.maintenance()
                        else if (isSuspended(room))
                          const StatusPill.suspended()
                        else if (openStatus.isKnown)
                          StatusPill.openStatus(openStatus)
                        else
                          const StatusPill(label: 'เปิดใช้งาน', icon: Icons.check_circle_rounded),
                      ],
                    ),
                    if (openStatus.isClosure) ...[
                      const SizedBox(height: 16),
                      _Notice(
                        icon: Icons.event_busy_rounded,
                        text: openStatus.detail == null ? 'วันนี้ปิดทำการเป็นกรณีพิเศษ' : 'วันนี้ปิดทำการ: ${openStatus.detail}',
                      ),
                    ],
                    if (isMaintenance(room)) ...[
                      const SizedBox(height: 16),
                      _Notice(
                        icon: Icons.build_rounded,
                        text: statusReasonOf(room) == null
                            ? 'ห้องนี้กำลังปิดปรับปรุง อาจไม่สามารถใช้งานได้ในขณะนี้'
                            : 'ห้องนี้กำลังปิดปรับปรุง: ${statusReasonOf(room)}',
                      ),
                    ],
                    if (isSuspended(room)) ...[
                      const SizedBox(height: 16),
                      _Notice(
                        icon: Icons.block_rounded,
                        text: statusReasonOf(room) == null
                            ? 'ห้องนี้งดใช้งานชั่วคราว ไม่สามารถใช้งานได้ในขณะนี้'
                            : 'ห้องนี้งดใช้งานชั่วคราว: ${statusReasonOf(room)}',
                      ),
                    ],
                    const SizedBox(height: 18),
                    _MiniMap(room: room, onOpen: _openMap),
                    ..._buildPanoramaSection(),
                    if (kTourEnabled && room['tour_point_id'] != null && room['building_id'] != null) ...[
                      const SizedBox(height: 12),
                      _TourEntry(
                        onTap: () => openTour(
                          context,
                          buildingId: room['building_id'],
                          buildingName: buildingName,
                          pointId: room['tour_point_id'],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    const _SectionHeader(icon: Icons.info_outline_rounded, title: 'ข้อมูลห้องและสิ่งอำนวยความสะดวก'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: appCardDecoration(radius: 18),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _InfoRow(icon: Icons.apartment_rounded, label: 'อาคาร', value: buildingName),
                          const Divider(),
                          _InfoRow(icon: Icons.layers_rounded, label: 'ชั้น', value: floorLabel(floor)),
                          if (hasRoomType) ...[
                            const Divider(),
                            _InfoRow(icon: Icons.category_rounded, label: 'ประเภท', value: roomType),
                          ],
                          if (hasCapacity) ...[
                            const Divider(),
                            _InfoRow(icon: Icons.groups_rounded, label: 'ความจุ', value: '$capacity ที่นั่ง'),
                          ],
                          if (facilities.isNotEmpty) ...[
                            const Divider(),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const _IconTile(Icons.grid_view_rounded),
                                      const SizedBox(width: 12),
                                      Text('สิ่งอำนวยความสะดวก', style: TextStyle(color: AppColors.muted, fontSize: 14, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 48),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [for (final (icon, label) in facilities) _AmenityChip(icon, label)],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (hours != null) ...[
                      const SizedBox(height: 22),
                      const _SectionHeader(icon: Icons.schedule_rounded, title: 'เวลาทำการ'),
                      const SizedBox(height: 10),
                      HoursCard(rows: weeklyHoursRows(hours), inheritsBuilding: room['open_hours'] == null),
                    ],
                    const SizedBox(height: 22),
                    ReportLinkCard(onTap: () => showReportSheet(context, room: room)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -3))],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              if (_panoramas.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: const StadiumBorder(),
                      backgroundColor: AppColors.surface,
                    ),
                    onPressed: _openPanorama,
                    icon: const Icon(Icons.threesixty_rounded, size: 20),
                    label: const Text('ภาพ 360°', maxLines: 1, softWrap: false),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                  onPressed: _openMap,
                  icon: const Icon(Icons.location_on_rounded, size: 20),
                  label: const Text('ดูบนแผนที่'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// แถบบน: ย้อนกลับ + "รายละเอียดห้อง" + แชร์ + ดาวห้องโปรด (ดาวเด้งเล็กน้อยทุกครั้งที่สลับ)
class _DetailHeader extends StatelessWidget {
  final bool isFavorite;
  final bool loadingFavorite;
  final VoidCallback onFavorite;
  final Future<void> Function(BuildContext buttonContext) onShare;

  const _DetailHeader({
    required this.isFavorite,
    required this.loadingFavorite,
    required this.onFavorite,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
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
            child: Text(
              'รายละเอียดห้อง',
              style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'แชร์ห้องนี้',
              onPressed: () => onShare(buttonContext),
              icon: Icon(Icons.share_outlined, size: 21, color: AppColors.muted),
            ),
          ),
          IconButton(
            tooltip: isFavorite ? 'นำออกจากห้องโปรด' : 'บันทึกเป็นห้องโปรด',
            onPressed: loadingFavorite ? null : onFavorite,
            icon: AnimatedSwitcher(
              duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                child: child,
              ),
              child: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                key: ValueKey(isFavorite),
                color: isFavorite ? AppColors.primary : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// หัวข้อส่วนมีไอคอนเขียวนำหน้า (และป้ายเล็กทางขวาได้)
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        ),
        ?trailing,
      ],
    );
  }
}

class _SoftPill extends StatelessWidget {
  final String label;

  const _SoftPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// กล่องแจ้งเตือนสีส้มอ่อน (ปิดปรับปรุง / ปิดทำการพิเศษ)
class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.ink, height: 1.4))),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;

  const _IconTile(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 20, color: AppColors.primary),
    );
  }
}

/// ทางเข้าหน้าเดินชม: เริ่มเดินจากจุดที่ผู้ดูแลผูกไว้กับห้องนี้ (เช่น ทางเดินหน้าห้อง)
class _TourEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _TourEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: appCardDecoration(),
            child: Row(
              children: [
                const IconBadge(Icons.directions_walk_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'เดินชมจากหน้าห้องนี้',
                        style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'เดินดูทางเดินและห้องรอบ ๆ แบบ 360°',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// แผนที่ย่อ: ผังชั้นของห้องนี้พร้อมหมุดที่ไฮไลต์ แตะเพื่อเปิดแผนที่เต็ม
/// โหลดผังไม่ได้ก็ไม่ทำให้หน้ารายละเอียดพัง แค่แสดงข้อความแทน
class _MiniMap extends StatefulWidget {
  final Map<String, dynamic> room;
  final VoidCallback onOpen;

  const _MiniMap({required this.room, required this.onOpen});

  @override
  State<_MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<_MiniMap> {
  late final Future<FloorPlan?> _future = _load();

  Future<FloorPlan?> _load() async {
    final building = widget.room['building_name']?.toString();
    if (building == null) return null;
    try {
      return await Api.floorPlan(building, floorOf(widget.room));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FloorPlan?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Shimmer(child: AspectRatio(aspectRatio: 1.45, child: SkeletonBox(radius: 16)));
        }
        final plan = snapshot.data;
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onOpen,
            child: Ink(
              decoration: appCardDecoration(radius: 18).copyWith(
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: plan == null ? _buildNoPlan() : _buildPlan(plan),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoPlan() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const IconBadge(Icons.map_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ยังไม่มีแผนผังของ${floorLabel(floorOf(widget.room))}',
                  style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'แตะเพื่อดูรายชื่อห้องในชั้นนี้',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }

  Widget _buildPlan(FloorPlan plan) {
    final pinned = hasPin(widget.room);
    final x = (double.tryParse('${widget.room['pin_x']}') ?? 0) / 100;
    final y = (double.tryParse('${widget.room['pin_y']}') ?? 0) / 100;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: plan.aspectRatio,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Image(
                    image: CachedNetworkImageProvider(plan.imageUrl),
                    fit: BoxFit.fill,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 36),
                    ),
                  ),
                ),
                if (pinned)
                  Positioned(
                    left: box.maxWidth * x - _PulsingPin.size / 2,
                    top: box.maxHeight * y - _PulsingPin.size / 2,
                    child: const _PulsingPin(label: ''),
                  ),
                // ป้ายรหัสห้องมุมซ้ายบน (แทนป้ายเหนือหมุด จึงไม่บังรายละเอียดในผัง)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(
                          widget.room['room_code']?.toString() ?? '',
                          style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // แถบใต้รูป: ไม่ทับแผนผัง จึงไม่บังหมุดหรือคำอธิบายสีในรูป
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              Icon(
                pinned ? Icons.location_on_rounded : Icons.info_outline_rounded,
                size: 18,
                color: pinned ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pinned
                      ? [
                          floorLabel(floorOf(widget.room)),
                          if ((widget.room['room_type']?.toString() ?? '').isNotEmpty) widget.room['room_type'].toString(),
                        ].join(' • ')
                      : 'ห้องนี้ยังไม่ได้ปักหมุดบนแผนผัง',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'แผนที่เต็ม',
                style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 3),
              Icon(Icons.north_east_rounded, size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ],
    );
  }
}

/// ภาพย่อของภาพ 360° แรกของห้อง (ตัดส่วนกลางภาพ) พร้อมจำนวนมุมและปุ่มเปิดดู
class _PanoramaPreview extends StatelessWidget {
  final List<Map<String, dynamic>> panoramas;
  final VoidCallback onOpen;

  const _PanoramaPreview({required this.panoramas, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final first = panoramas.first;
    final label = first['position_label']?.toString();
    final count = panoramas.length;

    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 208,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ภาพ 360° (2:1) ขอบบน/ล่างคือเพดาน/พื้นที่ถูกยืด จึงขยายเข้าไปเอาช่วงกลาง (ระดับสายตา) มาแสดง
              Transform.scale(
                scale: 1.4,
                child: Image.network(
                  Api.assetUrl(first['image_url'].toString()),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.fill,
                    child: Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 36),
                  ),
                ),
              ),
              // ไล่เงาด้านล่างให้ข้อความอ่านออกบนภาพทุกแบบ
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
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: Icon(Icons.threesixty_rounded, color: AppColors.primary, size: 30),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label != null && label.isNotEmpty ? label : 'ภาพ 360° ภายในห้อง',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            count > 1 ? '$count มุม · แตะเพื่อดูรอบทิศ' : 'แตะเพื่อดูรอบทิศ',
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                      child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
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

/// หมุดของห้องนี้: วงแหวนกระเพื่อมรอบจุด พร้อมป้ายรหัสห้องด้านบน
class _PulsingPin extends StatefulWidget {
  static const size = 48.0;

  final String label;

  const _PulsingPin({required this.label});

  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final color = AppColors.primary;

    return SizedBox(
      width: _PulsingPin.size,
      height: _PulsingPin.size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              final t = still ? 0.5 : _controller.value;
              return Container(
                width: 18 + 30 * t,
                height: 18 + 30 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.35 * (1 - t)),
                ),
              );
            },
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
          if (widget.label.isNotEmpty)
            Positioned(
              bottom: _PulsingPin.size / 2 + 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10241A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _IconTile(icon),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: AppColors.ink, fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmenityChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AmenityChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
