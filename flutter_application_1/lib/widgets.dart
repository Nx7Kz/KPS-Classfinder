import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'motion.dart';
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

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: AppColors.ink, fontSize: 16),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'ล้างคำค้นหา',
              icon: Icon(Icons.close_rounded, color: AppColors.muted),
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

enum _PillTone { normal, warning, muted }

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

  /// ป้าย "เปิดอยู่" (เขียว) / "ปิดอยู่" (เทา) จากเวลาทำการ [short] = ข้อความสั้นสำหรับรายการ
  StatusPill.openStatus(OpenStatus status, {super.key, bool short = false})
      : label = short ? status.shortLabel : status.label,
        icon = Icons.schedule_rounded,
        _tone = status.state == OpenState.open ? _PillTone.normal : _PillTone.muted;

  @override
  Widget build(BuildContext context) {
    final color = switch (_tone) {
      _PillTone.warning => AppColors.warning,
      _PillTone.muted => AppColors.muted,
      _PillTone.normal => AppColors.primary,
    };
    final background = switch (_tone) {
      _PillTone.warning => AppColors.warningTint,
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
  final IconData icon;

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
    this.icon = Icons.meeting_room_rounded,
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
    final openStatus = roomOpenStatus(room);

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
                IconBadge(icon),
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
                          if (hasPanorama(room)) ...[
                            const SizedBox(width: 8),
                            const StatusPill(label: '360°', icon: Icons.threesixty_rounded),
                          ],
                          if (isMaintenance(room)) ...[const SizedBox(width: 8), const StatusPill.maintenance()],
                          if (openStatus.isKnown && !isMaintenance(room)) ...[
                            const SizedBox(width: 8),
                            StatusPill.openStatus(openStatus, short: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // ค้นหาได้ทั้งชื่ออาคารและประเภทห้อง จึงไฮไลต์บรรทัดเหล่านี้ด้วย
                      HighlightText(
                        where,
                        query: highlight,
                        maxLines: 1,
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      if (summary != null)
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

void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}
