import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'offline_cache.dart';
import 'open_status.dart';
import 'room_utils.dart';

/// หัวข้อใหญ่ของแต่ละแท็บ
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.4)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// ช่องค้นหาแบบพื้นเทาอ่อนมุมมน
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  /// ทรงแคปซูลพื้นขาวขอบบาง (หน้าค้นหาหลัก) ปิด = ทรงเดิมพื้นเทาอ่อน
  final bool pill;

  /// 0 = ขนาดปกติ, 1 = ย่อเล็กสุด (ใช้กับแถบค้นหาที่ย่อลงเมื่อเลื่อนหน้า) มีผลเฉพาะทรง [pill]
  final double shrink;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.pill = false,
    this.shrink = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = shrink.clamp(0.0, 1.0);
    final iconSize = 24 - 4 * t;
    final fieldHeight = 48 - 14 * t; // ความสูงขั้นต่ำของไอคอนหน้า/หลังช่อง
    OutlineInputBorder pillBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: AppColors.ink, fontSize: 16 - 2 * t),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        hintText: hint,
        fillColor: pill ? AppColors.surface : null,
        contentPadding: pill ? EdgeInsets.symmetric(horizontal: 18, vertical: 16 - 7 * t) : null,
        border: pill ? pillBorder(AppColors.line) : null,
        enabledBorder: pill ? pillBorder(AppColors.line) : null,
        focusedBorder: pill ? pillBorder(AppColors.primary, 1.5) : null,
        prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary, size: iconSize),
        prefixIconConstraints: pill ? BoxConstraints(minWidth: 48 - 4 * t, minHeight: fieldHeight) : null,
        suffixIconConstraints: pill ? BoxConstraints(minWidth: 48 - 4 * t, minHeight: fieldHeight) : null,
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'ล้างคำค้นหา',
              icon: Icon(Icons.close_rounded, color: AppColors.muted, size: iconSize),
              onPressed: () {
                controller.clear();
                onChanged?.call('');
              },
            );
          },
        ),
      ),
    );
  }
}

/// ไอคอนในกรอบสี่เหลี่ยมมนพื้นเขียวอ่อน
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? background;
  final Color? color;

  const IconBadge(
    this.icon, {
    super.key,
    this.size = 44,
    this.background,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? AppColors.tint,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color ?? AppColors.primary, size: size * 0.5),
    );
  }
}

/// แถบเตือนใต้แถบสถานะเมื่อแอปเชื่อมต่อเซิร์ฟเวอร์ไม่ได้และกำลังแสดงข้อมูลที่แคชไว้ (หายเองเมื่อโหลดสดได้อีกครั้ง)
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: OfflineCache.offlineSince,
      builder: (context, since, _) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: since == null
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                color: AppColors.warningTint,
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 17, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ออฟไลน์ • แสดงข้อมูลที่บันทึกไว้เมื่อ ${formatSyncTime(since)}',
                        style: TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

enum _PillTone { normal, warning, danger, muted }

/// ป้ายสถานะเล็ก ๆ เช่น "ปิดปรับปรุง"
class StatusPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final _PillTone _tone;

  const StatusPill({super.key, required this.label, this.icon}) : _tone = _PillTone.normal;

  const StatusPill.maintenance({super.key})
      : label = 'ปิดปรับปรุง',
        icon = Icons.build_rounded,
        _tone = _PillTone.warning;

  const StatusPill.suspended({super.key})
      : label = 'งดใช้งาน',
        icon = Icons.block_rounded,
        _tone = _PillTone.danger;

  /// ป้าย "เปิดอยู่" (เขียว) / "ปิดอยู่" (เทา) จากเวลาทำการ [short] = ข้อความสั้นสำหรับรายการ
  StatusPill.openStatus(OpenStatus status, {super.key, bool short = false})
      : label = short ? status.shortLabel : status.label,
        icon = Icons.schedule_rounded,
        _tone = status.state == OpenState.open ? _PillTone.normal : _PillTone.muted;

  @override
  Widget build(BuildContext context) {
    final color = switch (_tone) {
      _PillTone.warning => AppColors.warning,
      _PillTone.danger => AppColors.danger,
      _PillTone.muted => AppColors.muted,
      _PillTone.normal => AppColors.primary,
    };
    final background = switch (_tone) {
      _PillTone.warning => AppColors.warningTint,
      _PillTone.danger => AppColors.dangerTint,
      _PillTone.muted => AppColors.fill,
      _PillTone.normal => AppColors.tint,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// แถวห้องเรียนมาตรฐาน ใช้ในผลค้นหา / รายการห้อง / รายการโปรด
class RoomTile extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  final bool showBuilding;
  final Widget? trailing;

  /// null = เลือกไอคอนตามประเภทห้องอัตโนมัติ
  final IconData? icon;

  /// ลำดับในรายการ ใส่แล้วการ์ดจะค่อย ๆ ปรากฏไล่ตามลำดับ (null = ไม่มีแอนิเมชันเข้า)
  final int? entranceIndex;

  /// คำค้นที่จะไฮไลต์ในรหัสห้อง (ไม่สนตัวพิมพ์เล็ก/ใหญ่) ว่างหรือ null = ไม่ไฮไลต์
  final String? highlight;

  const RoomTile({
    super.key,
    required this.room,
    required this.onTap,
    this.showBuilding = true,
    this.trailing,
    this.icon,
    this.highlight,
    this.entranceIndex,
  });

  @override
  Widget build(BuildContext context) {
    final code = room['room_code']?.toString() ?? '-';
    final where = [
      if (showBuilding) room['building_name']?.toString() ?? '-',
      floorLabel(floorOf(room)),
    ].join(' · ');
    final summary = roomSummary(room);

    final tile = Pressable(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: appCardDecoration(),
            child: Row(
              children: [
                IconBadge(icon ?? roomIcon(room)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: HighlightText(
                              code,
                              query: highlight,
                              maxLines: 1,
                              style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          // ไม่แสดงป้าย 360° / เปิดอยู่ ข้างรหัสห้อง เพื่อให้เห็นรหัสห้องเต็ม (ข้อมูลเหล่านี้ดูได้ในหน้ารายละเอียดห้อง)
                          if (isMaintenance(room)) ...[const SizedBox(width: 8), const StatusPill.maintenance()],
                          if (isSuspended(room)) ...[const SizedBox(width: 8), const StatusPill.suspended()],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // ค้นหาได้ทั้งชื่ออาคารและประเภทห้อง จึงไฮไลต์บรรทัดเหล่านี้ด้วย
                      HighlightText(
                        // ในรายการของอาคารเดียว (ไม่แสดงชื่ออาคาร) รวมชั้นกับประเภท/ความจุไว้บรรทัดเดียว
                        showBuilding || summary == null ? where : '$where • $summary',
                        query: highlight,
                        maxLines: 1,
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      if (summary != null && showBuilding)
                        HighlightText(
                          summary,
                          query: highlight,
                          maxLines: 1,
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
    final index = entranceIndex;
    return index == null ? tile : FadeSlideIn(index: index, child: tile);
  }
}

/// ข้อความที่ไฮไลต์ทุกช่วงที่ตรงกับ [query] (ไม่สนตัวพิมพ์เล็ก/ใหญ่) ด้วยพื้นเขียวอ่อน + สีเขียว
/// ช่วยให้เห็นทันทีว่าผลลัพธ์แต่ละรายการตรงกับคำค้นตรงไหน
class HighlightText extends StatelessWidget {
  final String text;
  final String? query;
  final TextStyle style;
  final int? maxLines;

  const HighlightText(this.text, {super.key, required this.query, required this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final q = query?.trim().toLowerCase() ?? '';
    final lower = text.toLowerCase();
    if (q.isEmpty || !lower.contains(q)) {
      return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    }

    final match = style.copyWith(color: AppColors.primary, backgroundColor: AppColors.tint);
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(q, start);
      if (index < 0) break;
      if (index > start) spans.add(TextSpan(text: text.substring(start, index)));
      spans.add(TextSpan(text: text.substring(index, index + q.length), style: match));
      start = index + q.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// หน้าจอสถานะกลางจอ: ว่าง / ผิดพลาด (มีปุ่มลองใหม่)
class StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  const StateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  factory StateView.error(Object error, {VoidCallback? onRetry}) {
    final connection = error is ApiException && error.isConnection;
    return StateView(
      icon: connection ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: connection ? 'เชื่อมต่อไม่ได้' : 'เกิดข้อผิดพลาด',
      message: error is ApiException ? error.message : 'ไม่สามารถโหลดข้อมูลได้ ลองใหม่อีกครั้ง',
      actionLabel: onRetry == null ? null : 'ลองอีกครั้ง',
      onAction: onRetry,
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon,
              size: 64,
              background: isError ? AppColors.dangerTint : AppColors.tint,
              color: isError ? AppColors.danger : AppColors.primary,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(140, 46)),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// แถบชิปเลื่อนแนวนอน (เลือกอาคาร / ชั้น)
class ChipRow extends StatelessWidget {
  final List<String> labels;
  final String? selected;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  const ChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final label = labels[index];
          final isSelected = label == selected;
          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            labelStyle: TextStyle(
              color: isSelected ? AppColors.onPrimary : AppColors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            onSelected: (_) {
              if (!isSelected) Haptics.select();
              onSelected(label);
            },
          );
        },
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'ยืนยัน',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message, style: TextStyle(color: AppColors.muted, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('ยกเลิก', style: TextStyle(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel, style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// แถบบนมาตรฐานของหน้าหลัก: โลโก้ + ชื่อแอป และปุ่มทางขวา (พื้นขาว มีเส้นบางด้านล่าง)
class AppTopBar extends StatelessWidget {
  final List<Widget> actions;

  /// ใส่แล้วแสดงสองบรรทัด: "KPS CLASSFINDER" ตัวเล็กด้านบน + [title] ตัวหนาเขียวด้านล่าง
  final String? title;

  const AppTopBar({super.key, this.actions = const [], this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, actions.isEmpty ? 20 : 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.tint, shape: BoxShape.circle),
            child: Icon(Icons.school_rounded, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: title == null
                ? Text(
                    'KPS ClassFinder',
                    style: TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KPS CLASSFINDER',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                      Text(
                        title!,
                        style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.2),
                      ),
                    ],
                  ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// ปุ่มแคปซูลสำหรับแถวตัวเลือก (อาคาร/ชั้น/คำค้นลัด): เลือกอยู่ = เขียวเต็ม ไม่ได้เลือก = ขาวมีขอบ
class PillButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  const PillButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.onPrimary : AppColors.muted;
    return Pressable(
      child: Material(
        color: active ? AppColors.primary : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: active ? AppColors.primary : AppColors.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            if (!active) Haptics.select();
            onTap();
          },
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 17, color: color), const SizedBox(width: 6)],
                Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}

/// ตารางเวลาทำการรายสัปดาห์ (จันทร์ → อาทิตย์) ไฮไลต์แถววันนี้
class HoursCard extends StatelessWidget {
  final List<HoursRow> rows;
  final bool inheritsBuilding;

  const HoursCard({super.key, required this.rows, this.inheritsBuilding = false});

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
                  if (row.isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
                      child: Text('วันนี้', style: TextStyle(color: AppColors.onPrimary, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
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
