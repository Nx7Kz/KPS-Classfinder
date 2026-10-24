import 'package:flutter/material.dart';

import 'app_theme.dart';

/// โครงร่างระหว่างโหลด (skeleton): แสดงรูปทรงจาง ๆ ของเนื้อหาที่กำลังจะมา
/// พร้อมแสงวิ่งผ่าน (shimmer) แทนวงกลมหมุน ทำให้รู้สึกว่าโหลดเร็วกว่าและหน้าไม่กระโดด
///
/// วิธีใช้: ห่อกลุ่มของ [SkeletonBox] ด้วย [Shimmer] ตัวเดียว แสงจะวิ่งต่อเนื่องทั้งกลุ่ม
class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  // สร้างเมื่อต้องใช้จริงเท่านั้น (ผู้ใช้ที่ปิดแอนิเมชันจะไม่มีตัวควบคุม) กันสร้างตอน dispose
  AnimationController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ผู้ใช้ที่ปิดแอนิเมชันในเครื่อง (การช่วยการเข้าถึง) จะเห็นโครงร่างนิ่ง ๆ ไม่มีแสงวิ่ง
    if (MediaQuery.of(context).disableAnimations) return widget.child;

    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    final base = AppColors.line;
    final highlight = AppColors.dark ? const Color(0xFF34473C) : const Color(0xFFF4F8F5);

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = controller.value * 3 - 1; // เลื่อนจาก -1 ถึง 2 ให้แสงเข้า-ออกนอกขอบได้พอดี
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, highlight, base],
            stops: [t - 0.3, t, t + 0.3].map((s) => s.clamp(0.0, 1.0)).toList(),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// กล่องสีจางหนึ่งชิ้นของโครงร่าง (ไม่ระบุ width/height = ขยายเต็มพื้นที่)
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const SkeletonBox({super.key, this.width, this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// โครงร่างของ RoomTile (ไอคอน + 2 บรรทัด) ใช้กับรายการห้องและรายการอาคารแบบย่อ
class RoomTileSkeleton extends StatelessWidget {
  final double titleWidth;

  const RoomTileSkeleton({super.key, this.titleWidth = 110});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: appCardDecoration(),
      child: Row(
        children: [
          const SkeletonBox(width: 44, height: 44, radius: 13),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: titleWidth, height: 15),
                const SizedBox(height: 9),
                const SkeletonBox(width: 170, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// โครงร่างของการ์ดอาคารในแท็บ "อาคาร"
class BuildingCardSkeleton extends StatelessWidget {
  const BuildingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: appCardDecoration(radius: 18),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 48, height: 48, radius: 14),
              SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 44, height: 11),
                  SizedBox(height: 8),
                  SkeletonBox(width: 180, height: 15),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(height: 11),
          SizedBox(height: 8),
          SkeletonBox(width: 200, height: 11),
          SizedBox(height: 16),
          Row(
            children: [
              SkeletonBox(width: 72, height: 26, radius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 72, height: 26, radius: 999),
            ],
          ),
        ],
      ),
    );
  }
}

/// รายการโครงร่างแบบเลื่อนไม่ได้ ใช้แทนรายการระหว่างโหลด
class SkeletonList extends StatelessWidget {
  final int count;
  final Widget Function(int index) itemBuilder;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final Widget? header;

  const SkeletonList({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.spacing = 10,
    this.header,
  });

  /// รายการห้อง ความกว้างชื่อห้องสลับกันเล็กน้อยให้ดูเป็นธรรมชาติ
  factory SkeletonList.rooms({int count = 5, EdgeInsetsGeometry padding = EdgeInsets.zero, Widget? header}) {
    const widths = [110.0, 90.0, 130.0, 100.0];
    return SkeletonList(
      count: count,
      padding: padding,
      header: header,
      itemBuilder: (i) => RoomTileSkeleton(titleWidth: widths[i % widths.length]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // เลื่อนไม่ได้ แต่ห่อด้วย scroll view กันล้นจอบนเครื่องจอเตี้ย
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ?header,
            for (var i = 0; i < count; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              itemBuilder(i),
            ],
          ],
        ),
      ),
    );
  }
}

/// หัวข้อย่อยจำลอง (ขนาดเท่า SectionTitle)
class SectionTitleSkeleton extends StatelessWidget {
  final double width;

  const SectionTitleSkeleton({super.key, this.width = 120});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: SkeletonBox(width: width, height: 14),
    );
  }
}

/// แถวชิปจำลอง (เลือกอาคาร/ชั้น)
class ChipRowSkeleton extends StatelessWidget {
  final List<double> widths;

  const ChipRowSkeleton({super.key, required this.widths});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (var i = 0; i < widths.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SkeletonBox(width: widths[i], height: 36, radius: 999),
          ],
        ],
      ),
    );
  }
}

/// โครงร่างหน้าแผนที่: แถวชิป + กรอบแผนที่ + แถบด้านล่าง
class MapSkeleton extends StatelessWidget {
  final bool showBuildingChips;

  const MapSkeleton({super.key, this.showBuildingChips = true});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showBuildingChips) ...[
              const ChipRowSkeleton(widths: [120, 150]),
              const SizedBox(height: 10),
            ],
            const ChipRowSkeleton(widths: [56, 56, 56]),
            const SizedBox(height: 10),
            const Expanded(child: SkeletonBox(radius: 16)),
            const SizedBox(height: 10),
            const SkeletonBox(height: 92, radius: 18),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}
