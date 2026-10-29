import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'room_detail_screen.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// เปิด/ปิดระบบเดินชม: false = ซ่อนทุกทางเข้า (แท็บล่าง, การ์ดในหน้าห้อง) โค้ด/ฐานข้อมูล/API ฝั่ง backend ยังอยู่ครบ
const bool kTourEnabled = true;

/// เปิดหน้าเดินชมอาคารแบบ Street View (เริ่มที่จุดหน้าห้อง ถ้าระบุ pointId)
Future<void> openTour(BuildContext context, {required Object buildingId, String? buildingName, Object? pointId}) async {
  Haptics.tap();
  if (kIsWeb) {
    // WebView ใช้บนเว็บไม่ได้ (ไม่มี implementation) จึงเปิดหน้าเดินชมของเซิร์ฟเวอร์ในแท็บใหม่แทน
    final url = ApiConfig.endpoint('tour/').replace(
      queryParameters: {'building': '$buildingId', if (pointId != null) 'point': '$pointId', 'theme': AppColors.dark ? 'dark' : 'light'},
    );
    final opened = await launchUrl(url, webOnlyWindowName: '_blank');
    if (!opened && context.mounted) showAppSnack(context, 'เปิดหน้าเดินชมไม่ได้ ลองใหม่อีกครั้ง');
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TourViewerScreen(buildingId: buildingId, buildingName: buildingName, pointId: pointId),
    ),
  );
}

/// แท็บ "เดินชม": อาคารที่มีภาพ 360° ให้เดินดูภายใน
class TourScreen extends StatefulWidget {
  const TourScreen({super.key});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  late Future<List<Map<String, dynamic>>> _future = Api.tourBuildings();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> buildings) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return buildings;
    return buildings
        .where((b) => '${b['name'] ?? ''} ${b['code'] ?? ''}'.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _refresh() async {
    final future = Api.tourBuildings();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // ข้อผิดพลาดแสดงในหน้าจออยู่แล้ว
    }
  }

  Widget _searchField({double shrink = 0}) => AppSearchField(
        controller: _searchController,
        hint: 'ค้นหาชื่ออาคารหรือรหัสตึก...',
        pill: true,
        shrink: shrink,
        onChanged: (value) => setState(() => _query = value),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final buildings = snapshot.data ?? const <Map<String, dynamic>>[];
        // มีรายการแล้ว: ทั้งหน้าเลื่อนไปด้วยกัน หัวข้อเลื่อนหายไป เหลือแถบค้นหาย่อเล็กค้างด้านบน
        if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && buildings.isNotEmpty) {
          return _buildList(context, _filter(buildings));
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TourBadge(),
              const SizedBox(height: 8),
              const PageHeader(title: 'เดินชมอาคาร', subtitle: 'ดูภายในอาคารแบบ 360° เลือกจุดจากแผนที่ย่อได้ตามต้องการ'),
              const SizedBox(height: 14),
              _searchField(),
              const SizedBox(height: 12),
              Expanded(child: _buildState(snapshot)),
            ],
          ),
        );
      },
    );
  }

  /// กำลังโหลด / โหลดไม่สำเร็จ / ยังไม่มีอาคาร
  Widget _buildState(AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return SkeletonList(count: 2, spacing: 12, itemBuilder: (_) => const BuildingCardSkeleton());
    }
    if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _refresh);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 420,
            child: StateView(
              icon: Icons.threesixty_rounded,
              title: 'ยังไม่มีอาคารที่เปิดให้เดินชม',
              message: 'ผู้ดูแลกำลังเตรียมภาพ 360° ของอาคาร ลองกลับมาดูใหม่ภายหลัง',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Map<String, dynamic>> shown) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TourBadge(),
                  SizedBox(height: 8),
                  PageHeader(title: 'เดินชมอาคาร', subtitle: 'ดูภายในอาคารแบบ 360° เลือกจุดจากแผนที่ย่อได้ตามต้องการ'),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
              background: Theme.of(context).scaffoldBackgroundColor,
              builder: (shrink) => _searchField(shrink: shrink),
            ),
          ),
          SliverPadding(
            // รายการสั้น ๆ เติมที่ว่างท้ายหน้า ให้เลื่อนได้พอที่หัวข้อจะเลื่อนหายและแถบค้นหาย่อลง
            padding: EdgeInsets.fromLTRB(20, 4, 20, shown.length <= 3 ? 170 : 24),
            sliver: SliverList.separated(
              // แถวแรก = ข้อความแนะนำ + จำนวนอาคาร
              itemCount: shown.length + 1 + (shown.isEmpty ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) return _TourIntro(count: shown.length);
                if (shown.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: StateView(
                      icon: Icons.search_off_rounded,
                      title: 'ไม่พบอาคารที่ค้นหา',
                      message: 'ลองค้นด้วยชื่อหรือรหัสตึกอื่น',
                    ),
                  );
                }
                return FadeSlideIn(
                  index: index - 1,
                  child: Pressable(child: _TourBuildingCard(building: shown[index - 1])),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบค้นหาที่ค้างบนสุดของหน้า: ตอนเลื่อนลงจะย่อความสูง/ตัวอักษรลง เหลือพื้นที่ให้รายการมากขึ้น
class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final Color background;
  final Widget Function(double shrink) builder;

  const _SearchBarDelegate({required this.background, required this.builder});

  static const _maxHeight = 76.0;
  static const _minHeight = 52.0;

  @override
  double get maxExtent => _maxHeight;

  @override
  double get minExtent => _minHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (_maxHeight - _minHeight)).clamp(0.0, 1.0);
    // SliverPersistentHeader ส่งข้อจำกัดความสูงแบบหลวม จึงกำหนดความสูงเองให้เท่าส่วนที่ยังเหลือ ไม่งั้นความสูงจริงน้อยกว่าที่แจ้งไว้
    return SizedBox(
      height: (_maxHeight - shrinkOffset).clamp(_minHeight, _maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border(bottom: BorderSide(color: AppColors.line.withValues(alpha: t))),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Align(alignment: Alignment.center, child: builder(t)),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchBarDelegate oldDelegate) => true;
}

/// ป้ายเล็กเหนือหัวข้อ
class _TourBadge extends StatelessWidget {
  const _TourBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'ทัวร์เสมือนจริง 360°',
            style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// กล่องแนะนำวิธีใช้ + จำนวนอาคาร
class _TourIntro extends StatelessWidget {
  final int count;

  const _TourIntro({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.touch_app_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สำรวจง่าย ๆ ในมุม 360°',
                      style: TextStyle(color: AppColors.ink, fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ลากเพื่อหมุนมอง แล้วแตะจุดบนแผนที่ย่อมุมซ้ายล่างเพื่อไปดูจุดอื่น',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'อาคารที่เดินชมได้ · $count อาคาร',
          style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _TourBuildingCard extends StatelessWidget {
  final Map<String, dynamic> building;

  const _TourBuildingCard({required this.building});

  @override
  Widget build(BuildContext context) {
    final name = building['name']?.toString() ?? '-';
    final code = building['code']?.toString() ?? '';
    final points = building['point_count']?.toString() ?? '0';
    final floors = building['floor_count']?.toString() ?? '1';
    final cover = building['cover_image']?.toString();
    final plan = building['floor_plan_image']?.toString();
    final image = (cover != null && cover.isNotEmpty) ? cover : plan;
    void start() => openTour(context, buildingId: building['id'], buildingName: name);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: start,
        child: Ink(
          decoration: appCardDecoration(radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Container(
                    height: 150,
                    width: double.infinity,
                    color: image == cover ? AppColors.fill : const Color(0xFFF7F8F6),
                    child: image == null || image.isEmpty
                        ? Icon(Icons.threesixty_rounded, color: AppColors.muted, size: 44)
                        : Image.network(
                            Api.assetUrl(image),
                            fit: image == cover ? BoxFit.cover : BoxFit.contain,
                            loadingBuilder: (context, child, progress) =>
                                progress == null ? child : const Shimmer(child: SkeletonBox(radius: 0)),
                            errorBuilder: (_, _, _) => Icon(Icons.threesixty_rounded, color: AppColors.muted, size: 44),
                          ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.threesixty_rounded, size: 15, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            '360°',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (code.isNotEmpty)
                            Text(
                              code,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          Text(
                            name,
                            style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _MetaChip(icon: Icons.place_outlined, label: '$points จุดสำรวจ'),
                              _MetaChip(icon: Icons.layers_outlined, label: '$floors ชั้น'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: start,
                      icon: const Icon(Icons.directions_walk_rounded, size: 20),
                      label: const Text('เดินชม'),
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

/// หน้าเดินชมเต็มจอ: เปิดหน้า /tour/ ของเซิร์ฟเวอร์ใน WebView (Photo Sphere Viewer)
/// หน้าเว็บส่งข้อความกลับผ่าน channel "KpsApp": {type: 'close'} หรือ {type: 'room', code}
class TourViewerScreen extends StatefulWidget {
  final Object buildingId;
  final String? buildingName;
  final Object? pointId;

  const TourViewerScreen({super.key, required this.buildingId, this.buildingName, this.pointId});

  @override
  State<TourViewerScreen> createState() => _TourViewerScreenState();
}

class _TourViewerScreenState extends State<TourViewerScreen> {
  static const _background = Color(0xFF0D1511);

  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  bool _openingRoom = false;

  Uri get _url => ApiConfig.endpoint('tour/').replace(
    queryParameters: {
      'building': '${widget.buildingId}',
      if (widget.pointId != null) 'point': '${widget.pointId}',
      'embed': 'app',
      'theme': AppColors.dark ? 'dark' : 'light',
    },
  );

  @override
  void initState() {
    super.initState();
    final origin = Uri.parse(ApiConfig.baseUrl).origin;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_background)
      ..addJavaScriptChannel('KpsApp', onMessageReceived: (message) => _onMessage(message.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false || !mounted) return;
            setState(() {
              _failed = true;
              _loading = false;
            });
          },
          // เปิดได้เฉพาะหน้าในเซิร์ฟเวอร์ของแอป (กันลิงก์ภายนอกโหลดใน WebView)
          onNavigationRequest: (request) => request.url.startsWith(origin)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadRequest(_url);
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _controller.loadRequest(_url);
  }

  Future<void> _onMessage(String raw) async {
    Map<String, dynamic> message;
    try {
      message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    switch (message['type']) {
      case 'close':
        if (mounted) Navigator.of(context).maybePop();
      case 'room':
        await _openRoom(message['code']?.toString());
    }
  }

  Future<void> _openRoom(String? code) async {
    if (code == null || code.isEmpty || _openingRoom) return;
    _openingRoom = true;
    Haptics.tap();
    try {
      final room = await Api.roomByCode(code);
      if (!mounted) return;
      if (room == null) {
        showAppSnack(context, 'ไม่พบข้อมูลห้อง $code');
      } else {
        await openRoom(context, room);
      }
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      _openingRoom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              if (_loading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: _background,
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80))),
                  ),
                ),
              if (_failed)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.background,
                    child: StateView(
                      icon: Icons.wifi_off_rounded,
                      title: 'เปิดหน้าเดินชมไม่สำเร็จ',
                      message: 'ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้ง',
                      actionLabel: 'ลองใหม่',
                      onAction: _retry,
                    ),
                  ),
                ),
              if (_failed || _loading)
                Positioned(
                  left: 8,
                  top: 8,
                  child: IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, color: _failed ? AppColors.ink : Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
