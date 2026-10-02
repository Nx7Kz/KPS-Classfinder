import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// แอนิเมชันเล็ก ๆ และการสั่นตอบสนองที่ใช้ร่วมกันทั้งแอป
/// ทุกตัวเคารพการตั้งค่า "ลดการเคลื่อนไหว" ของเครื่อง (MediaQuery.disableAnimations)

bool reduceMotion(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// การสั่นเบา ๆ (มีผลเฉพาะมือถือจริง เครื่องจำลอง/เว็บจะเงียบ)
class Haptics {
  const Haptics._();

  /// เลือก/สลับตัวเลือก เช่น แตะหมุด สลับชั้น สลับแท็บ
  static void select() => HapticFeedback.selectionClick();

  /// การกระทำที่มีผล เช่น บันทึกห้องโปรด ลบรายการ
  static void tap() => HapticFeedback.lightImpact();
}

/// ค่อย ๆ จางและเลื่อนขึ้นตอนปรากฏครั้งแรก รายการลำดับหลังเริ่มช้ากว่านิดหน่อย (ไล่กันเป็นลำดับ)
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;

  const FadeSlideIn({super.key, required this.child, this.index = 0});

  static const _step = 45; // ms ต่อรายการ
  static const _base = 260; // ms ของแต่ละรายการ
  static const _maxStagger = 8; // รายการหลังจากนี้ไม่หน่วงเพิ่ม กันรายการยาวรอนาน

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;

    final delay = index.clamp(0, _maxStagger) * _step;
    final total = delay + _base;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
    );
  }
}

/// ยุบลงนิดหนึ่งตอนนิ้วกดค้าง ให้รู้ว่ากดโดนแล้ว (ไม่ยุ่งกับการรับแตะของลูก)
class Pressable extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  const Pressable({super.key, required this.child, this.pressedScale = 0.975});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
