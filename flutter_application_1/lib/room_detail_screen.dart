import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'motion.dart';
import 'open_status.dart';
import 'panorama_screen.dart';
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
      const SectionTitle('ภาพ 360°'),
      if (!_panoramasLoaded)
        const Shimmer(child: SkeletonBox(height: 190, radius: 16))
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดห้อง'),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'แชร์ห้องนี้',
              onPressed: () => _share(buttonContext),
              icon: const Icon(Icons.share_rounded, size: 21),
            ),
          ),
          IconButton(
            tooltip: _isFavorite ? 'นำออกจากห้องโปรด' : 'บันทึกเป็นห้องโปรด',
            onPressed: _isLoadingFavorite ? null : _toggleFavorite,
            // ดาวเด้งขึ้นเล็กน้อยทุกครั้งที่สลับ (ปิดเองเมื่อเครื่องตั้งลดการเคลื่อนไหว)
            icon: AnimatedSwitcher(
              duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                child: child,
              ),
              child: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                key: ValueKey(_isFavorite),
                color: _isFavorite ? AppColors.primary : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            roomCode,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(buildingName, style: TextStyle(color: AppColors.muted, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(label: floorLabel(floor), icon: Icons.layers_rounded),
              if (roomType != null && roomType.isNotEmpty)
                StatusPill(label: roomType, icon: Icons.category_rounded),
              if (isMaintenance(room))
                const StatusPill.maintenance()
              else if (openStatus.isKnown)
                StatusPill.openStatus(openStatus)
              else
                const StatusPill(label: 'เปิดใช้งาน', icon: Icons.check_circle_rounded),
            ],
          ),
          if (openStatus.isClosure) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warningTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.event_busy_rounded, color: AppColors.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      openStatus.detail == null ? 'วันนี้ปิดทำการเป็นกรณีพิเศษ' : 'วันนี้ปิดทำการ: ${openStatus.detail}',
                      style: TextStyle(color: AppColors.ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isMaintenance(room)) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warningTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.build_rounded, color: AppColors.warning, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ห้องนี้กำลังปิดปรับปรุง อาจไม่สามารถใช้งานได้ในขณะนี้',
                      style: TextStyle(color: AppColors.ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SectionTitle('ตำแหน่งในอาคาร'),
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
          const SectionTitle('ข้อมูลห้อง'),
          Container(
            decoration: appCardDecoration(),
            child: Column(
              children: [
                _InfoRow(icon: Icons.apartment_rounded, label: 'อาคาร', value: buildingName),
                const Divider(indent: 56),
                _InfoRow(icon: Icons.layers_rounded, label: 'ชั้น', value: floorLabel(floor)),
                if (capacity != null && capacity.isNotEmpty) ...[
                  const Divider(indent: 56),
                  _InfoRow(icon: Icons.event_seat_rounded, label: 'ความจุ', value: '$capacity ที่นั่ง'),
                ],
              ],
            ),
          ),
          if (hours != null) ...[
            const SectionTitle('เวลาทำการ'),
            _HoursCard(rows: weeklyHoursRows(hours), inheritsBuilding: room['open_hours'] == null),
          ],
          if (amenities.isNotEmpty) ...[
            const SectionTitle('สิ่งอำนวยความสะดวก'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (amenities['seats'] != null)
                  _AmenityChip(Icons.event_seat_rounded, '${amenities['seats']} ที่นั่ง'),
                if (amenities['outlets'] != null)
                  _AmenityChip(Icons.power_rounded, '${amenities['outlets']} จุดปลั๊กไฟ'),
                if (amenities['ac'] != null)
                  _AmenityChip(Icons.ac_unit_rounded, '${amenities['ac']} เครื่องปรับอากาศ'),
                if (amenities['wifi'] != null) _AmenityChip(Icons.wifi_rounded, '${amenities['wifi']}'),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              if (_panoramas.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openPanorama,
                    icon: const Icon(Icons.threesixty_rounded, size: 20),
                    label: const Text('ภาพ 360°', maxLines: 1, softWrap: false),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
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
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onOpen,
            child: Ink(
              decoration: appCardDecoration(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
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
                  child: Image.network(
                    plan.imageUrl,
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
                    child: _PulsingPin(label: widget.room['room_code']?.toString() ?? ''),
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
                      ? '${floorLabel(floorOf(widget.room))} · ${widget.room['room_code'] ?? ''}'
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
              const SizedBox(width: 4),
              Icon(Icons.open_in_full_rounded, size: 16, color: AppColors.primary),
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
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 190,
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
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.threesixty_rounded, color: Colors.white, size: 30),
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
                    const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 18),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 16),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// ตารางเวลาทำการรายสัปดาห์ (จันทร์ → อาทิตย์) ไฮไลต์แถววันนี้
class _HoursCard extends StatelessWidget {
  final List<HoursRow> rows;
  final bool inheritsBuilding;

  const _HoursCard({required this.rows, required this.inheritsBuilding});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: appCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final row in rows)
            Container(
              color: row.isToday ? AppColors.tint : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      row.day,
                      style: TextStyle(
                        color: row.isToday ? AppColors.primary : AppColors.ink,
                        fontSize: 14.5,
                        fontWeight: row.isToday ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (row.isToday) const StatusPill(label: 'วันนี้'),
                  const Spacer(),
                  Text(
                    row.text,
                    style: TextStyle(
                      color: row.isClosed ? AppColors.muted : AppColors.ink,
                      fontSize: 14.5,
                      fontWeight: row.isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (inheritsBuilding)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Text('ใช้ตามเวลาทำการของอาคาร', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(12)),
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
