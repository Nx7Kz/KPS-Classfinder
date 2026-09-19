import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

import 'api_client.dart';
import 'app_theme.dart';
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
  int _index = 0;
  bool _imageReady = false;
  bool _imageFailed = false;

  Map<String, dynamic> get _current => widget.panoramas[_index];

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

  IconData _iconFor(String? type) {
    switch (type) {
      case 'door':
        return Icons.door_front_door_rounded;
      case 'stairs':
        return Icons.stairs_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.arrow_upward_rounded;
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
            width: 96,
            height: 78,
            widget: GestureDetector(
              onTap: () => _followHotspot(hotspot),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: Icon(_iconFor(hotspot['icon_type']?.toString()), color: AppColors.onPrimary, size: 22),
                  ),
                  if (label.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
    final label = panorama['position_label']?.toString();
    final roomCode = widget.room['room_code']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PanoramaViewer(
            key: ValueKey(panorama['id']),
            minZoom: 1,
            maxZoom: 3,
            hotspots: _buildHotspots(),
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
          if (!_imageReady && !_imageFailed)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoundButton(icon: Icons.arrow_back_rounded, tooltip: 'กลับ', onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roomCode,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          if (label != null && label.isNotEmpty)
                            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ลากเพื่อหมุนมอง · บีบนิ้วเพื่อซูม',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    if (widget.panoramas.length > 1) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: widget.panoramas.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final name = widget.panoramas[i]['position_label']?.toString();
                            final selected = i == _index;
                            return ChoiceChip(
                              label: Text(name != null && name.isNotEmpty ? name : 'มุมที่ ${i + 1}'),
                              selected: selected,
                              onSelected: (_) => _go(i),
                              labelStyle: TextStyle(
                                color: selected ? AppColors.onPrimary : AppColors.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: Colors.white)),
    );
  }
}
