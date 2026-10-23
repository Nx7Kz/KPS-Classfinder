import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'widgets.dart';

/// หัวข้อที่ผู้ใช้เลือกแจ้ง (ค่า key ต้องตรงกับที่เซิร์ฟเวอร์รับ)
const _categories = [
  ('wrong_info', 'ข้อมูลห้องไม่ถูกต้อง', Icons.edit_note_rounded),
  ('wrong_location', 'ตำแหน่งหมุดไม่ตรง', Icons.pin_drop_outlined),
  ('wrong_status', 'สถานะ/เวลาทำการไม่ตรง', Icons.schedule_rounded),
  ('wrong_360', 'ภาพ 360° มีปัญหา', Icons.threesixty_rounded),
  ('other', 'อื่น ๆ', Icons.chat_bubble_outline_rounded),
];

/// เปิดแผ่นแจ้งข้อมูลไม่ถูกต้อง ระบุห้อง ([room]) หรืออาคาร ([building]) ได้ ถ้าไม่ระบุจะเป็นการแจ้งทั่วไป
/// ส่งสำเร็จแล้วปิดแผ่นพร้อมแจ้งผล
Future<void> showReportSheet(BuildContext context, {Map<String, dynamic>? room, Map<String, dynamic>? building}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(room: room, building: building),
  );
  if (sent == true && context.mounted) {
    showAppSnack(context, 'ส่งรายงานแล้ว ขอบคุณที่ช่วยแจ้ง ผู้ดูแลจะตรวจสอบข้อมูลให้');
  }
}

/// แถวลิงก์ท้ายหน้ารายละเอียด ชวนแจ้งผู้ดูแลเมื่อข้อมูลไม่ตรง
class ReportLinkCard extends StatelessWidget {
  final VoidCallback onTap;
  final String title;

  const ReportLinkCard({super.key, required this.onTap, this.title = 'ข้อมูลห้องนี้ไม่ตรง?'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: appCardDecoration(radius: 16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.flag_outlined, size: 20, color: AppColors.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: AppColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                    Text('แจ้งผู้ดูแลให้ตรวจสอบและแก้ไข', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  final Map<String, dynamic>? room;
  final Map<String, dynamic>? building;

  const _ReportSheet({this.room, this.building});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _message = TextEditingController();
  final _contact = TextEditingController();
  String? _category;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  String get _target {
    final room = widget.room;
    if (room != null) return '${room['room_code'] ?? ''} • ${room['building_name'] ?? ''}';
    final building = widget.building;
    if (building != null) return building['name']?.toString() ?? '';
    return 'ทั่วไป (ไม่ระบุห้อง)';
  }

  Future<void> _submit() async {
    final category = _category;
    final text = _message.text.trim();
    if (category == null) {
      setState(() => _error = 'กรุณาเลือกหัวข้อที่ต้องการแจ้ง');
      return;
    }
    if (text.length < 5) {
      setState(() => _error = 'กรุณาอธิบายอย่างน้อย 5 ตัวอักษร');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    // แจ้งระดับห้องส่ง room_id อย่างเดียว (เซิร์ฟเวอร์หาอาคารเอง) ระดับอาคารส่ง building_id
    final Object? roomId = widget.room?['id'];
    final Object? buildingId = widget.room != null ? null : widget.building?['id'];
    try {
      await Api.sendReport(
        category: category,
        message: text,
        contact: _contact.text,
        roomId: roomId,
        buildingId: buildingId,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('แจ้งข้อมูลไม่ถูกต้อง', style: TextStyle(color: AppColors.ink, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 15, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(_target, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 13))),
              ],
            ),
            const SizedBox(height: 16),
            Text('เรื่องที่พบ', style: TextStyle(color: AppColors.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, label, icon) in _categories)
                  PillButton(
                    label: label,
                    icon: icon,
                    active: _category == key,
                    onTap: () => setState(() {
                      _category = key;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'รายละเอียด',
                hintText: 'เช่น ป้ายหน้าห้องเป็น 301 แต่ในแอปเป็น 302',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contact,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'ช่องทางติดต่อกลับ (ไม่บังคับ)',
                hintText: 'อีเมล เบอร์โทร หรือไอดีไลน์',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 17, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13))),
                ],
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50), shape: const StadiumBorder()),
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_sending ? 'กำลังส่ง...' : 'ส่งรายงาน'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ข้อมูลที่ส่งจะถูกส่งให้ผู้ดูแลระบบเท่านั้น',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
