import 'package:flutter/material.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'app_theme.dart';
import 'room_store.dart';
import 'widgets.dart';

const appVersion = '1.0.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTaps = 0;
  DateTime? _lastVersionTap;

  void _onVersionTap() {
    final now = DateTime.now();
    final recent = _lastVersionTap != null && now.difference(_lastVersionTap!) < const Duration(seconds: 2);
    _versionTaps = recent ? _versionTaps + 1 : 1;
    _lastVersionTap = now;
    if (_versionTaps >= 5) {
      _versionTaps = 0;
      _editServer();
    }
  }

  Future<void> _editServer() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ServerDialog(),
    );
    if (changed == true && mounted) {
      showAppSnack(context, 'บันทึกที่อยู่เซิร์ฟเวอร์แล้ว รีเฟรชหน้าอาคารหรือแผนที่เพื่อโหลดข้อมูลใหม่');
    }
  }

  Future<void> _clear({
    required String title,
    required String message,
    required Future<void> Function() action,
    required String done,
  }) async {
    final ok = await confirmDialog(context, title: title, message: message, confirmLabel: 'ลบ');
    if (!ok) return;
    await action();
    if (mounted) showAppSnack(context, done);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const PageHeader(title: 'ตั้งค่า', subtitle: 'การเชื่อมต่อและข้อมูลในเครื่อง'),
        const SectionTitle('การแสดงผล'),
        const _ThemePicker(),
        const SectionTitle('ข้อมูลในเครื่อง'),
        _Group(
          children: [
            _SettingRow(
              icon: Icons.bookmark_remove_outlined,
              title: 'ล้างห้องโปรด',
              subtitle: 'ลบห้องที่บันทึกไว้ทั้งหมด',
              onTap: () => _clear(
                title: 'ล้างห้องโปรด?',
                message: 'ห้องที่บันทึกไว้ทั้งหมดจะถูกลบออกจากเครื่องนี้',
                action: RoomStore.clearFavorites,
                done: 'ล้างห้องโปรดแล้ว',
              ),
            ),
            _SettingRow(
              icon: Icons.history_rounded,
              title: 'ล้างประวัติการดู',
              subtitle: 'ลบรายการห้องที่ดูล่าสุด',
              onTap: () => _clear(
                title: 'ล้างประวัติการดู?',
                message: 'รายการห้องที่ดูล่าสุดจะถูกลบออกจากเครื่องนี้',
                action: RoomStore.clearRecents,
                done: 'ล้างประวัติแล้ว',
              ),
            ),
          ],
        ),
        const SectionTitle('เกี่ยวกับ'),
        _Group(
          children: [
            const _SettingRow(
              icon: Icons.school_rounded,
              title: 'KPS ClassFinder',
              subtitle: 'ค้นหาห้องเรียนและดูตำแหน่งบนแผนที่ภายในอาคาร',
            ),
            // ซ่อนการตั้งค่าเซิร์ฟเวอร์ไว้สำหรับผู้พัฒนา: แตะ "เวอร์ชัน" 5 ครั้งติดกันเพื่อเปิด
            GestureDetector(
              onTap: _onVersionTap,
              child: const _SettingRow(
                icon: Icons.info_outline_rounded,
                title: 'เวอร์ชัน',
                subtitle: appVersion,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// เลือกโหมดสี: ตามระบบ / สว่าง / มืด
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  static const _options = [
    (ThemeMode.system, 'ตามระบบ', Icons.brightness_auto_rounded),
    (ThemeMode.light, 'สว่าง', Icons.light_mode_rounded),
    (ThemeMode.dark, 'มืด', Icons.dark_mode_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, current, _) => Container(
        padding: const EdgeInsets.all(6),
        decoration: appCardDecoration(),
        child: Row(
          children: [
            for (final (mode, label, icon) in _options)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => ThemeController.set(mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: mode == current ? AppColors.tint : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(icon, size: 22, color: mode == current ? AppColors.primary : AppColors.muted),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: mode == current ? FontWeight.w700 : FontWeight.w500,
                            color: mode == current ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: appCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 72),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingRow({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            IconBadge(icon, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// กล่องแก้ไขที่อยู่เซิร์ฟเวอร์ พร้อมปุ่มทดสอบการเชื่อมต่อก่อนบันทึก
class _ServerDialog extends StatefulWidget {
  const _ServerDialog();

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController _controller = TextEditingController(text: ApiConfig.baseUrl);
  String? _error;
  String? _testResult;
  bool _testOk = false;
  bool _testing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _controller.text.trim();
    if (!ApiConfig.isValid(url)) {
      setState(() => _error = 'ที่อยู่ต้องขึ้นต้นด้วย http:// หรือ https://');
      return;
    }
    setState(() {
      _error = null;
      _testing = true;
      _testResult = null;
    });
    try {
      await Api.ping(url);
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = 'เชื่อมต่อสำเร็จ';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = error.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (!ApiConfig.isValid(url)) {
      setState(() => _error = 'ที่อยู่ต้องขึ้นต้นด้วย http:// หรือ https://');
      return;
    }
    await ApiConfig.save(url);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _reset() async {
    await ApiConfig.reset();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ที่อยู่เซิร์ฟเวอร์'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(hintText: 'http://192.168.1.10:3000', errorText: _error),
            onChanged: (_) => setState(() {
              _error = null;
              _testResult = null;
            }),
          ),
          const SizedBox(height: 10),
          Text(
            'เครื่องจริงต้องใช้ IP ของคอมพิวเตอร์ที่รันเซิร์ฟเวอร์ (ไม่ใช่ localhost)',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
          ),
          if (_testing || _testResult != null) ...[
            const SizedBox(height: 12),
            if (_testing)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
            else
              Row(
                children: [
                  Icon(
                    _testOk ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 18,
                    color: _testOk ? AppColors.primary : AppColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(color: _testOk ? AppColors.primary : AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(onPressed: _reset, child: Text('ค่าเริ่มต้น', style: TextStyle(color: AppColors.muted))),
        TextButton(onPressed: _testing ? null : _test, child: const Text('ทดสอบ')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 42)),
          onPressed: _save,
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
