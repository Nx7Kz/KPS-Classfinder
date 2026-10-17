import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'room_detail_screen.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// เปิดหน้าเดินชมอาคารแบบ Street View (เริ่มที่จุดหน้าห้อง ถ้าระบุ pointId)
Future<void> openTour(BuildContext context, {required Object buildingId, String? buildingName, Object? pointId}) {
  Haptics.tap();
  return Navigator.of(context).push(
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

  Future<void> _refresh() async {
    final future = Api.tourBuildings();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // ข้อผิดพลาดแสดงในหน้าจออยู่แล้ว
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: 'เดินชมอาคาร', subtitle: 'เดินดูภายในอาคารแบบ 360° เหมือน Street View'),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return SkeletonList(count: 2, spacing: 12, itemBuilder: (_) => const BuildingCardSkeleton());
                }
                if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _refresh);

                final buildings = snapshot.data ?? const [];
                if (buildings.isEmpty) {
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
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: buildings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => FadeSlideIn(
                      index: index,
                      child: Pressable(child: _TourBuildingCard(building: buildings[index])),
                    ),
                  ),
                );
              },
            ),
          ),
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
                          const SizedBox(height: 2),
                          Text(
                            '$points จุด · $floors ชั้น',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
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
