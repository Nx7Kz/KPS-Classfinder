import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_tabs.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'open_status.dart';
import 'building_detail_screen.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// ตัวกรองด่วนใต้ช่องค้นหา (คำนวณจากข้อมูลอาคารจริง)
enum _BuildingFilter { all, openNow, has360 }

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  late Future<List<Map<String, dynamic>>> _buildingsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _BuildingFilter _filter = _BuildingFilter.all;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _buildingsFuture = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final list = await Api.buildings();
    if (mounted) setState(() => _total = list.length);
    return list;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _buildingsFuture = future);
    try {
      await future;
    } catch (_) {
      // ข้อผิดพลาดแสดงในหน้าจออยู่แล้ว
    }
  }

  bool _matches(Map<String, dynamic> building) {
    if (_query.isNotEmpty) {
      final name = (building['name']?.toString() ?? '').toLowerCase();
      final code = (building['code']?.toString() ?? '').toLowerCase();
      if (!name.contains(_query) && !code.contains(_query)) return false;
    }
    switch (_filter) {
      case _BuildingFilter.all:
        return true;
      case _BuildingFilter.openNow:
        return buildingOpenStatus(building).state == OpenState.open;
      case _BuildingFilter.has360:
        return (int.tryParse('${building['panorama_room_count']}') ?? 0) > 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppTopBar(title: 'อาคารทั้งหมด'),
        Expanded(
          child: ColoredBox(
            color: AppColors.fill,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: AppSearchField(
                    pill: true,
                    controller: _searchController,
                    hint: 'ค้นหาชื่ออาคาร หรือรหัส เช่น LH3, KH80',
                    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      PillButton(
                        label: _total == 0 ? 'ทั้งหมด' : 'ทั้งหมด ($_total)',
                        active: _filter == _BuildingFilter.all,
                        onTap: () => setState(() => _filter = _BuildingFilter.all),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: 'เปิดอยู่ตอนนี้',
                        active: _filter == _BuildingFilter.openNow,
                        onTap: () => setState(() => _filter = _BuildingFilter.openNow),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: 'มีภาพ 360°',
                        active: _filter == _BuildingFilter.has360,
                        onTap: () => setState(() => _filter = _BuildingFilter.has360),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _buildingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SkeletonList(count: 3, spacing: 12, itemBuilder: (_) => const BuildingCardSkeleton()),
          );
        }

        if (snapshot.hasError) return StateView.error(snapshot.error!, onRetry: _refresh);

        final buildings = snapshot.data ?? const [];
        if (buildings.isEmpty) {
          return const StateView(
            icon: Icons.apartment_outlined,
            title: 'ยังไม่มีอาคารในระบบ',
            message: 'รอผู้ดูแลเพิ่มข้อมูลอาคาร',
          );
        }

        final visible = buildings.where(_matches).toList();
        if (visible.isEmpty) {
          return StateView(
            icon: Icons.search_off_rounded,
            title: _filter == _BuildingFilter.all ? 'ไม่พบอาคารที่ค้นหา' : 'ไม่มีอาคารที่ตรงเงื่อนไข',
            message: _filter == _BuildingFilter.openNow
                ? 'ตอนนี้ไม่มีอาคารที่เปิดอยู่ หรืออาคารยังไม่ได้ตั้งเวลาทำการ'
                : 'ลองค้นหาด้วยชื่ออื่น รหัสอาคาร หรือเปลี่ยนตัวกรอง',
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              for (final (index, building) in visible.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FadeSlideIn(
                    index: index,
                    child: Pressable(child: _BuildingCard(building: building, query: _query)),
                  ),
                ),
              const SizedBox(height: 4),
              _MapBanner(onTap: () => AppTabs.go(AppTabs.map)),
            ],
          ),
        );
      },
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final Map<String, dynamic> building;
  final String query;

  const _BuildingCard({required this.building, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final code = building['code']?.toString() ?? '-';
    final name = building['name']?.toString() ?? '-';
    final location = building['location']?.toString().trim() ?? '';
    final floorCount = building['floor_count']?.toString() ?? '0';
    final roomCount = building['room_count']?.toString() ?? '0';
    final panoRooms = int.tryParse('${building['panorama_room_count']}') ?? 0;
    final maintenance = int.tryParse('${building['maintenance_count']}') ?? 0;
    final openStatus = buildingOpenStatus(building);
    final hours = building['open_hours'];

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BuildingDetailScreen(building: building))),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: appCardDecoration(radius: 18).copyWith(
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(building: building, show360: panoRooms > 0),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(6)),
                            child: HighlightText(
                              code,
                              query: query,
                              maxLines: 1,
                              style: TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (openStatus.isKnown) _OpenDot(status: openStatus),
                      ],
                    ),
                    const SizedBox(height: 5),
                    HighlightText(
                      name,
                      query: query,
                      maxLines: 1,
                      style: TextStyle(color: AppColors.ink, fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Meta(icon: Icons.layers_outlined, label: '$floorCount ชั้น'),
                        _Meta(icon: Icons.meeting_room_outlined, label: '$roomCount ห้อง'),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (hours is Map)
                                  _Tag(icon: Icons.schedule_rounded, label: summarizeHours(Map<String, dynamic>.from(hours))),
                                if (panoRooms > 0) _Tag(icon: Icons.threesixty_rounded, label: 'ภาพ 360° $panoRooms ห้อง', accent: true),
                                if (maintenance > 0) _Tag(icon: Icons.build_rounded, label: 'ปิดปรับปรุง $maintenance ห้อง', warning: true),
                                if (location.isNotEmpty) _Tag(icon: Icons.place_outlined, label: location),
                                if (hours is! Map && panoRooms == 0 && maintenance == 0 && location.isEmpty)
                                  _Tag(label: 'ดูห้องทั้งหมด'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 1),
                            child: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                          ),
                        ],
                      ),
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

/// รูปย่อมุมโค้งซ้ายของการ์ด: รูปปก > แผนผังชั้น 1 > ไอคอน (มีป้าย 360° มุมซ้ายบนถ้าอาคารมีภาพ 360°)
class _Thumbnail extends StatelessWidget {
  final Map<String, dynamic> building;
  final bool show360;

  const _Thumbnail({required this.building, required this.show360});

  @override
  Widget build(BuildContext context) {
    final cover = building['cover_image']?.toString();
    final plan = building['floor_plan_image']?.toString();
    final hasCover = cover != null && cover.isNotEmpty;
    final hasPlan = plan != null && plan.isNotEmpty;

    Widget image;
    if (hasCover || hasPlan) {
      image = Container(
        color: hasCover ? AppColors.fill : const Color(0xFFF7F8F6),
        padding: hasCover ? EdgeInsets.zero : const EdgeInsets.all(4),
        child: Image(
          image: CachedNetworkImageProvider(Api.assetUrl(hasCover ? cover : plan!)),
          fit: hasCover ? BoxFit.cover : BoxFit.contain,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const Shimmer(child: SkeletonBox(radius: 0)),
          errorBuilder: (_, _, _) => Center(child: Icon(Icons.apartment_rounded, color: AppColors.muted, size: 32)),
        ),
      );
    } else {
      image = Container(
        color: AppColors.tint,
        child: Center(child: Icon(Icons.apartment_rounded, color: AppColors.primary, size: 34)),
      );
    }

    return SizedBox(
      width: 96,
      height: 96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (show360)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.threesixty_rounded, size: 11, color: AppColors.dark ? const Color(0xFF052E16) : Colors.white),
                      const SizedBox(width: 2),
                      Text(
                        '360°',
                        style: TextStyle(
                          color: AppColors.dark ? const Color(0xFF052E16) : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// จุดสีหน้าข้อความ "เปิดอยู่/ปิดอยู่" มุมขวาบนของการ์ด
class _OpenDot extends StatelessWidget {
  final OpenStatus status;

  const _OpenDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final open = status.state == OpenState.open;
    final color = open ? AppColors.primary : AppColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status.shortLabel, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Meta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool accent;
  final bool warning;

  const _Tag({this.icon, required this.label, this.accent = false, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.warning : (accent ? AppColors.primary : AppColors.muted);
    final background = warning ? AppColors.warningTint : (accent ? AppColors.tint : AppColors.fill);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// ป้ายท้ายรายการ: ชวนเปิดแท็บแผนที่เพื่อดูตำแหน่งห้องบนแผนผังชั้น
class _MapBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _MapBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onColor = AppColors.onPrimary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.dark ? AppColors.primary.withValues(alpha: 0.78) : AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: onColor.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(Icons.map_rounded, color: onColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ต้องการดูตำแหน่งห้องบนแผนที่?',
                      style: TextStyle(color: onColor, fontSize: 16, fontWeight: FontWeight.w800, height: 1.25),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'เปิดแผนผังแต่ละชั้นของอาคาร แล้วแตะหมุดเพื่อดูห้อง',
                      style: TextStyle(color: onColor.withValues(alpha: 0.82), fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Pressable(
            child: Material(
              color: AppColors.surface,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.explore_rounded, size: 19, color: AppColors.primaryDark),
                      const SizedBox(width: 8),
                      Text(
                        'เปิดแผนที่อาคาร',
                        style: TextStyle(color: AppColors.primaryDark, fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
