import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_theme.dart';
import 'room_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _buildings = [
    'อาคารเรียนรวม 3 (ศร.3)',
    'อาคารเรียน 80 ปี',
  ];

  String _selectedBuilding = _buildings[0];
  String? _selectedFloor;
  late Future<List<Map<String, dynamic>>> _roomsFuture;

  @override
  void initState() {
    super.initState();
    _roomsFuture = _fetchRooms(_selectedBuilding);
  }

  Future<List<Map<String, dynamic>>> _fetchRooms(String building) async {
    final url = ApiConfig.endpoint('api/building/${Uri.encodeComponent(building)}');
    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('โหลดข้อมูลห้องไม่สำเร็จ');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('รูปแบบข้อมูลไม่ถูกต้อง');
    }
    return decoded.map((room) => Map<String, dynamic>.from(room as Map)).toList();
  }

  void _selectBuilding(String building) {
    if (building == _selectedBuilding) return;
    setState(() {
      _selectedBuilding = building;
      _selectedFloor = null;
      _roomsFuture = _fetchRooms(building);
    });
  }

  List<String> _sortedFloors(List<Map<String, dynamic>> rooms) {
    final floors = rooms.map((room) => room['floor']?.toString() ?? '-').toSet().toList();
    floors.sort((first, second) {
      final firstNumber = int.tryParse(first);
      final secondNumber = int.tryParse(second);
      if (firstNumber != null && secondNumber != null) {
        return firstNumber.compareTo(secondNumber);
      }
      if (firstNumber != null) return -1;
      if (secondNumber != null) return 1;
      return first.compareTo(second);
    });
    return floors;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'แผนที่มหาวิทยาลัย',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'เลือกอาคารและชั้น แล้วแตะหมุดเพื่อดูรายละเอียดห้อง',
                style: TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _buildings.map(_buildBuildingChip).toList(),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuildingChip(String building) {
    final selected = building == _selectedBuilding;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _selectBuilding(building),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.line),
        ),
        child: Text(
          building,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _roomsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        if (snapshot.hasError) {
          return _buildStatusCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.redAccent,
            tint: const Color(0xFFFFEDED),
            title: 'เกิดข้อผิดพลาด',
            subtitle: '${snapshot.error}',
          );
        }

        final rooms = snapshot.data ?? const [];
        if (rooms.isEmpty) {
          return _buildStatusCard(
            icon: Icons.meeting_room_outlined,
            iconColor: AppColors.primary,
            tint: AppColors.blueTint,
            title: 'ยังไม่มีข้อมูลห้องเรียน',
            subtitle: 'ยังไม่มีห้องเรียนในอาคารนี้ในระบบ',
          );
        }

        final floors = _sortedFloors(rooms);
        _selectedFloor ??= floors.first;
        final roomsOnFloor = rooms
            .where((room) => (room['floor']?.toString() ?? '-') == _selectedFloor)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: floors.map((floor) {
                final selected = floor == _selectedFloor;
                return ChoiceChip(
                  label: Text('ชั้น $floor'),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _selectedFloor = floor),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  side: BorderSide(color: selected ? AppColors.accent : AppColors.line),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _FloorPlanMap(
                key: ValueKey('$_selectedBuilding-$_selectedFloor'),
                building: _selectedBuilding,
                floor: _selectedFloor!,
                rooms: roomsOnFloor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required Color tint,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: appCardDecoration(color: tint),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: iconColor,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// โหลด URL รูปแผนที่ของอาคาร+ชั้นที่เลือก แล้วส่งต่อให้ _InteractiveFloorPlan วาดหมุด
class _FloorPlanMap extends StatefulWidget {
  final String building;
  final String floor;
  final List<Map<String, dynamic>> rooms;

  const _FloorPlanMap({
    super.key,
    required this.building,
    required this.floor,
    required this.rooms,
  });

  @override
  State<_FloorPlanMap> createState() => _FloorPlanMapState();
}

class _FloorPlanMapState extends State<_FloorPlanMap> {
  late Future<String?> _imageUrlFuture;

  @override
  void initState() {
    super.initState();
    _imageUrlFuture = _loadFloorPlanUrl();
  }

  Future<String?> _loadFloorPlanUrl() async {
    final url = ApiConfig.endpoint('api/floorplan').replace(queryParameters: {
      'building': widget.building,
      'floor': widget.floor,
    });

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      final path = decoded is Map ? decoded['image']?.toString() : null;
      if (path == null) return null;

      final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
      return ApiConfig.endpoint(normalizedPath).toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _imageUrlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        final imageUrl = snapshot.data;
        if (imageUrl == null) {
          return Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: appCardDecoration(color: AppColors.blueTint),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.map_outlined, color: Colors.white, size: 32),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'ยังไม่มีแผนที่สำหรับชั้นนี้',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final pinnedRooms = widget.rooms
            .where((room) => room['pin_x'] != null && room['pin_y'] != null)
            .toList();

        return _InteractiveFloorPlan(imageUrl: imageUrl, rooms: pinnedRooms);
      },
    );
  }
}

/// แสดงรูปแผนที่แบบ pan/zoom ได้ พร้อมวาดหมุดตามตำแหน่ง % ของแต่ละห้อง
class _InteractiveFloorPlan extends StatefulWidget {
  final String imageUrl;
  final List<Map<String, dynamic>> rooms;

  const _InteractiveFloorPlan({required this.imageUrl, required this.rooms});

  @override
  State<_InteractiveFloorPlan> createState() => _InteractiveFloorPlanState();
}

class _InteractiveFloorPlanState extends State<_InteractiveFloorPlan> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant _InteractiveFloorPlan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _aspectRatio = null;
      _resolveImageSize();
    }
  }

  void _resolveImageSize() {
    final provider = NetworkImage(widget.imageUrl);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _aspectRatio = info.image.width / info.image.height);
    });

    _stream?.removeListener(_listener!);
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_aspectRatio == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Container(
      decoration: appCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: AspectRatio(
          aspectRatio: _aspectRatio!,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(widget.imageUrl, fit: BoxFit.fill),
                  ),
                  for (final room in widget.rooms) _buildPin(context, room, constraints),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPin(BuildContext context, Map<String, dynamic> room, BoxConstraints constraints) {
    final x = double.tryParse(room['pin_x'].toString()) ?? 0;
    final y = double.tryParse(room['pin_y'].toString()) ?? 0;
    const size = 20.0;

    return Positioned(
      left: constraints.maxWidth * (x / 100) - size / 2,
      top: constraints.maxHeight * (y / 100) - size / 2,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}
