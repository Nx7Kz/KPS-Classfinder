import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'room_detail_screen.dart';
import 'room_utils.dart';
import 'widgets.dart';

/// โหลดภาพ 360° ของห้องแล้วเปิดหน้าดูภาพ (ใช้จากแผนที่ที่ยังไม่ได้โหลดภาพไว้ล่วงหน้า)
Future<void> openPanorama(BuildContext context, Map<String, dynamic> room) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  void say(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  try {
    final panoramas = await Api.panoramas(room['id']);
    if (panoramas.isEmpty) {
      say('ห้องนี้ยังไม่มีภาพ 360°');
      return;
    }
    await navigator.push(
      MaterialPageRoute(builder: (_) => PanoramaScreen(room: room, panoramas: panoramas)),
    );
  } catch (error) {
    say(error is ApiException ? error.message : 'โหลดภาพ 360° ไม่สำเร็จ');
  }
}

/// ดูภาพ 360° ของห้อง ลากเพื่อหมุนมอง แตะจุดเชื่อมเพื่อเดินไปยังภาพถัดไป
/// yaw/pitch ที่ backend เก็บไว้ตรงกับ longitude/latitude ของ panorama_viewer
class PanoramaScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> panoramas;

  const PanoramaScreen({super.key, required this.room, required this.panoramas});

  @override
  State<PanoramaScreen> createState() => _PanoramaScreenState();
}

class _PanoramaScreenState extends State<PanoramaScreen> {
  static const _minZoom = 1.0;
  static const _maxZoom = 3.0;

  final PanoramaController _controller = PanoramaController();
  Timer? _hintTimer;

  int _index = 0;
  bool _imageReady = false;
  bool _imageFailed = false;
  bool _gyro = false;
  bool _drawerOpen = true;
  bool _hintVisible = true;

  Map<String, dynamic> get _current => widget.panoramas[_index];

  @override
  void initState() {
    super.initState();
    // คำแนะนำการหมุนภาพกลางจอ แสดงสั้น ๆ แล้วหายไปเอง ไม่บังภาพ
    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _hintVisible = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _imageReady = false;
      _imageFailed = false;
    });
  }

  void _followHotspot(Map<String, dynamic> hotspot) {
    final targetId = hotspot['target_panorama_id'];
    final targetIndex = targetId == null
        ? -1
        : widget.panoramas.indexWhere((p) => p['id'].toString() == targetId.toString());

    if (targetIndex >= 0) {
      _go(targetIndex);
    } else {
      final label = hotspot['label']?.toString();
      showAppSnack(context, label != null && label.isNotEmpty ? label : 'จุดข้อมูล');
    }
  }

  void _zoomBy(double factor) {
    final next = (_controller.getZoom() * factor).clamp(_minZoom, _maxZoom).toDouble();
    _controller.setZoom(next);
  }

  void _resetView() {
    _controller.setView(0, 0);
    _controller.setZoom(1);
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          initialBuilding: widget.room['building_name']?.toString(),
          initialFloor: floorOf(widget.room),
          focusRoom: widget.room,
        ),
      ),
    );
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'door':
        return Icons.door_front_door_rounded;
      case 'stairs':
        return Icons.stairs_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.north_east_rounded;
    }
  }

  List<Hotspot> _buildHotspots() {
    final hotspots = _current['hotspots'];
    if (hotspots is! List) return const [];

    return [
      for (final raw in hotspots.whereType<Map>())
        () {
          final hotspot = Map<String, dynamic>.from(raw);
          final label = hotspot['label']?.toString() ?? '';
          return Hotspot(
            latitude: double.tryParse('${hotspot['pitch']}') ?? 0,
            longitude: double.tryParse('${hotspot['yaw']}') ?? 0,
            width: 140,
            height: 82,
            widget: GestureDetector(
              onTap: () => _followHotspot(hotspot),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.28), shape: BoxShape.circle),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        child: Icon(_iconFor(hotspot['icon_type']?.toString()), color: AppColors.onPrimary, size: 19),
                      ),
                    ],
                  ),
                  if (label.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF15803D), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF0F5C2B), fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final panorama = _current;
    final imageUrl = Api.assetUrl(panorama['image_url'].toString());
    final roomCode = widget.room['room_code']?.toString() ?? '';
    final multiple = widget.panoramas.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PanoramaViewer(
            // เปลี่ยนภาพหรือเปิด/ปิดเซนเซอร์เอียงเครื่อง = สร้างตัวแสดงภาพใหม่
            key: ValueKey('${panorama['id']}-$_gyro'),
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            hotspots: _buildHotspots(),
            panoramaController: _controller,
            sensorControl: _gyro ? SensorControl.orientation : SensorControl.none,
            onImageLoad: () {
              if (mounted) setState(() => _imageReady = true);
            },
            child: Image.network(
              imageUrl,
              errorBuilder: (_, error, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_imageFailed) setState(() => _imageFailed = true);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
          // เงาไล่บน/ล่างบาง ๆ ให้แถบลอยอ่านง่ายบนภาพทุกแบบ (ไม่รับการแตะ)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x73000000), Color(0x00000000), Color(0x00000000), Color(0x99000000)],
                  stops: [0, 0.22, 0.6, 1],
                ),
              ),
            ),
          ),
          if (!_imageReady && !_imageFailed) const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_imageFailed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: DecoratedBox(
                  decoration: appCardDecoration(radius: 20),
                  child: const SizedBox(
                    height: 280,
                    child: StateView(
                      icon: Icons.broken_image_outlined,
                      title: 'โหลดภาพ 360° ไม่สำเร็จ',
                      message: 'ตรวจสอบการเชื่อมต่อแล้วลองใหม่อีกครั้ง',
                      isError: true,
                    ),
                  ),
                ),
              ),
            ),
          // คำแนะนำกลางจอ (หายเองหลังไม่กี่วินาที)
          if (_imageReady)
            Center(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hintVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.threesixty_rounded, size: 19, color: Color(0xFFB1F3AB)),
                        SizedBox(width: 8),
                        Text('ลากเพื่อหมุนมอง · บีบนิ้วเพื่อซูม', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // แถบบนแบบแคปซูล: ย้อนกลับ + ห้อง/ชั้น + อาคาร/มุมที่ดู
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Align(
                alignment: Alignment.topCenter,
                child: _TopCapsule(
                  roomCode: roomCode,
                  floor: floorLabel(floorOf(widget.room)),
                  subtitle: [
                    widget.room['building_name']?.toString() ?? '',
                    if ((panorama['position_label']?.toString() ?? '').isNotEmpty) panorama['position_label'].toString(),
                  ].where((part) => part.isNotEmpty).join(' • '),
                  counter: multiple ? '${_index + 1}/${widget.panoramas.length}' : null,
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          // ปุ่มควบคุมด้านขวา: ซูม/รีเซ็ต และเซนเซอร์เอียงเครื่อง (ไม่แสดงบนเว็บที่ไม่มีเซนเซอร์)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ControlStack(
                    children: [
                      _CtrlButton(icon: Icons.add_rounded, tooltip: 'ขยายภาพ', onTap: () => _zoomBy(1.4)),
                      _CtrlButton(icon: Icons.remove_rounded, tooltip: 'ย่อภาพ', onTap: () => _zoomBy(1 / 1.4)),
                      _CtrlButton(icon: Icons.center_focus_strong_rounded, tooltip: 'กลับมุมมองเริ่มต้น', onTap: _resetView),
                    ],
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 10),
                    _ControlStack(
                      children: [
                        _CtrlButton(
                          icon: Icons.screen_rotation_rounded,
                          tooltip: _gyro ? 'ปิดการหมุนตามการเอียงเครื่อง' : 'หมุนภาพตามการเอียงเครื่อง',
                          active: _gyro,
                          onTap: () => setState(() => _gyro = !_gyro),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ลิ้นชักล่าง: จุดชมภาพในห้อง + ปุ่มลัด
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _Drawer(
                  panoramas: widget.panoramas,
                  index: _index,
                  open: _drawerOpen,
                  onToggle: () => setState(() => _drawerOpen = !_drawerOpen),
                  onPick: _go,
                  onMap: _openMap,
                  onInfo: () => openRoom(context, widget.room),
                  onExit: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// พื้นแผ่นลอยโปร่งแสงตามธีม (ขาว/เข้ม) ใช้ซ้อนบนภาพ 360°
BoxDecoration _floatingDecoration({double radius = 20}) => BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 4))],
    );

class _TopCapsule extends StatelessWidget {
  final String roomCode;
  final String floor;
  final String subtitle;
  final String? counter;
  final VoidCallback onBack;

  const _TopCapsule({required this.roomCode, required this.floor, required this.subtitle, required this.counter, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: _floatingDecoration(radius: 999),
      child: Row(
        children: [
          Tooltip(
            message: 'กลับ',
            child: Material(
              color: AppColors.fill,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: SizedBox(width: 38, height: 38, child: Icon(Icons.arrow_back_rounded, size: 21, color: AppColors.ink)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        roomCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800, height: 1.2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(5)),
                      child: Text(floor, style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty)
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ],
            ),
          ),
          if (counter != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(999)),
              child: Text(counter!, style: TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _ControlStack extends StatelessWidget {
  final List<Widget> children;

  const _ControlStack({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: _floatingDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(width: 22, height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: AppColors.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _CtrlButton({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.tint : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: active ? AppColors.primary : AppColors.muted)),
        ),
      ),
    );
  }
}

/// ลิ้นชักล่าง: หัวข้อ + จำนวนจุดชม + แถวภาพย่อสลับมุม (เมื่อมีหลายภาพ) + ปุ่มลัด 3 ปุ่ม
/// แตะหัวข้อเพื่อพับ/กางลิ้นชัก (พับแล้วเหลือแต่ปุ่มลัด เห็นภาพเต็มขึ้น)
class _Drawer extends StatelessWidget {
  final List<Map<String, dynamic>> panoramas;
  final int index;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;
  final VoidCallback onMap;
  final VoidCallback onInfo;
  final VoidCallback onExit;

  const _Drawer({
    required this.panoramas,
    required this.index,
    required this.open,
    required this.onToggle,
    required this.onPick,
    required this.onMap,
    required this.onInfo,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final multiple = panoramas.length > 1;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _floatingDecoration(radius: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (multiple) ...[
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.hub_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'จุดชมภาพ 360° ในห้องนี้',
                        style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(999)),
                      child: Text('${panoramas.length} จุด', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
            if (open) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: panoramas.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _SceneCard(
                    panorama: panoramas[i],
                    number: i + 1,
                    active: i == index,
                    onTap: () => onPick(i),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Divider(color: AppColors.line, height: 1),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                flex: 12,
                child: _ActionButton(icon: Icons.map_rounded, label: 'ดูผังบนแผนที่', filled: true, onTap: onMap),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: _ActionButton(icon: Icons.info_outline_rounded, label: 'ข้อมูลห้อง', onTap: onInfo),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 8,
                child: _ActionButton(icon: Icons.close_fullscreen_rounded, label: 'ทางออก', subtle: true, onTap: onExit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  final Map<String, dynamic> panorama;
  final int number;
  final bool active;
  final VoidCallback onTap;

  const _SceneCard({required this.panorama, required this.number, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = panorama['position_label']?.toString() ?? '';
    final title = name.isNotEmpty ? name : 'มุมที่ $number';

    return Material(
      color: active ? AppColors.tint : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? AppColors.primary.withValues(alpha: 0.5) : AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ภาพ 360° (2:1) ตัดช่วงกลางเป็นภาพย่อ
                      Image.network(
                        Api.assetUrl(panorama['image_url'].toString()),
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                        errorBuilder: (_, _, _) => Container(color: AppColors.fill, child: Icon(Icons.threesixty_rounded, color: AppColors.muted, size: 20)),
                      ),
                      if (active)
                        Container(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          child: const Icon(Icons.visibility_rounded, color: Colors.white, size: 19),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? AppColors.primary : AppColors.ink, fontSize: 12, fontWeight: active ? FontWeight.w800 : FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (active) ...[
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                        ],
                        Text(active ? 'มุมมองปัจจุบัน' : 'จุดที่ $number', style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool subtle;

  const _ActionButton({required this.icon, required this.label, required this.onTap, this.filled = false, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onPrimary : (subtle ? AppColors.muted : AppColors.ink);
    return Material(
      color: filled ? AppColors.primary : (subtle ? AppColors.fill : AppColors.surface),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          decoration: filled
              ? null
              : BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: filled ? AppColors.onPrimary : (subtle ? AppColors.muted : AppColors.primary)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
