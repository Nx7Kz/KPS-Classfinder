import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'panorama_screen.dart';
import 'room_store.dart';
import 'room_utils.dart';
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
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final nowFavorite = await RoomStore.toggleFavorite(room);
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
    showAppSnack(context, nowFavorite ? 'บันทึกเป็นห้องโปรดแล้ว' : 'นำออกจากห้องโปรดแล้ว');
  }

  Future<void> _copy() async {
    final text = '${room['room_code']} · ${room['building_name']} · ${floorLabel(floorOf(room))}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnack(context, 'คัดลอกข้อมูลห้องแล้ว');
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดห้อง'),
        actions: [
          IconButton(
            tooltip: 'คัดลอกข้อมูลห้อง',
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
          IconButton(
            tooltip: _isFavorite ? 'นำออกจากห้องโปรด' : 'บันทึกเป็นห้องโปรด',
            onPressed: _isLoadingFavorite ? null : _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _isFavorite ? AppColors.primary : AppColors.muted,
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
              if (!isMaintenance(room))
                const StatusPill(label: 'เปิดใช้งาน', icon: Icons.check_circle_rounded)
              else
                const StatusPill.maintenance(),
            ],
          ),
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
          if (!hasPin(room)) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ห้องนี้ยังไม่มีหมุดบนแผนที่ แต่ยังเปิดดูแผนที่ชั้นนี้ได้',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
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
