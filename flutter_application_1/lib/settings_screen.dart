import 'package:flutter/material.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'app_prefs.dart';
import 'app_theme.dart';
import 'guide_screen.dart';
import 'report_sheet.dart';
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
  int _favoriteCount = 0;
  int _recentCount = 0;

  // สถานะการเชื่อมต่อเซิร์ฟเวอร์ ตรวจเมื่อผู้ใช้แตะเท่านั้น (ไม่ยิงเรียกเองทุกครั้งที่เปิดหน้า)
  bool _checking = false;
  bool? _serverOk;

  @override
  void initState() {
    super.initState();
    RoomStore.revision.addListener(_loadCounts);
    _loadCounts();
  }

  @override
  void dispose() {
    RoomStore.revision.removeListener(_loadCounts);
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final favorites = await RoomStore.loadFavorites();
    final recents = await RoomStore.loadRecents();
    if (!mounted) return;
    setState(() {
      _favoriteCount = favorites.length;
      _recentCount = recents.length;
    });
  }

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
      setState(() => _serverOk = null);
      showAppSnack(context, 'บันทึกที่อยู่เซิร์ฟเวอร์แล้ว รีเฟรชหน้าอาคารหรือแผนที่เพื่อโหลดข้อมูลใหม่');
    }
  }

  Future<void> _checkServer() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _serverOk = null;
    });
    try {
      await Api.ping(ApiConfig.baseUrl);
      if (mounted) setState(() => _serverOk = true);
    } catch (_) {
      if (mounted) setState(() => _serverOk = false);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _clear({
    required String title,
    required String message,
    required Future<void> Function() action,
    required String done,
    required int count,
  }) async {
    if (count == 0) {
      showAppSnack(context, 'ยังไม่มีรายการให้ล้าง');
      return;
    }
    final ok = await confirmDialog(context, title: title, message: message, confirmLabel: 'ลบ');
    if (!ok) return;
    await action();
    if (mounted) showAppSnack(context, done);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppTopBar(),
        Expanded(
          child: ColoredBox(
            color: AppColors.fill,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: PageHeader(title: 'ตั้งค่า', subtitle: 'การแสดงผลและข้อมูลในเครื่อง'),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.tune_rounded, size: 26, color: AppColors.primary),
                    ),
                  ],
                ),
                const _Heading('การแสดงผล'),
                const _ThemePicker(),
                const SizedBox(height: 12),
                _Group(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: AppPrefs.alwaysShowLabels,
                      builder: (_, value, _) => _SettingRow(
                        icon: Icons.label_outline_rounded,
                        title: 'แสดงชื่อห้องบนแผนที่ตลอดเวลา',
                        subtitle: 'ไม่ซ่อนรหัสห้องเมื่อซูมออก',
                        trailing: Switch(value: value, onChanged: AppPrefs.setAlwaysShowLabels),
                        onTap: () => AppPrefs.setAlwaysShowLabels(!value),
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: AppPrefs.mapLabelLarge,
                      builder: (_, large, _) => _SettingRow(
                        icon: Icons.format_size_rounded,
                        title: 'ขนาดตัวอักษรบนแผนที่',
                        subtitle: large ? 'ใหญ่ (อ่านง่ายขึ้น)' : 'ปกติ',
                        trailing: _SizeToggle(large: large, onChanged: AppPrefs.setMapLabelLarge),
                      ),
                    ),
                  ],
                ),
                _Heading(
                  'ข้อมูลในเครื่อง',
                  trailing: Text(
                    'เก็บเฉพาะในเครื่องนี้',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),
                _Group(
                  children: [
                    _SettingRow(
                      icon: Icons.bookmark_remove_outlined,
                      title: 'ล้างห้องโปรด',
                      subtitle: 'ลบห้องที่บันทึกไว้ทั้งหมด',
                      badge: _favoriteCount > 0 ? '$_favoriteCount ห้อง' : null,
                      onTap: () => _clear(
                        title: 'ล้างห้องโปรด?',
                        message: 'ห้องที่บันทึกไว้ทั้งหมดจะถูกลบออกจากเครื่องนี้',
                        action: RoomStore.clearFavorites,
                        done: 'ล้างห้องโปรดแล้ว',
                        count: _favoriteCount,
                      ),
                    ),
                    _SettingRow(
                      icon: Icons.history_rounded,
                      title: 'ล้างประวัติการดู',
                      subtitle: 'ลบรายการห้องที่ดูล่าสุด',
                      badge: _recentCount > 0 ? '$_recentCount ห้อง' : null,
                      onTap: () => _clear(
                        title: 'ล้างประวัติการดู?',
                        message: 'รายการห้องที่ดูล่าสุดจะถูกลบออกจากเครื่องนี้',
                        action: RoomStore.clearRecents,
                        done: 'ล้างประวัติแล้ว',
                        count: _recentCount,
                      ),
                    ),
                  ],
                ),
                const _Heading('ช่วยเหลือ'),
                _Group(
                  children: [
                    _SettingRow(
                      icon: Icons.help_outline_rounded,
                      title: 'คู่มือการใช้งานและคำถามที่พบบ่อย',
                      subtitle: 'วิธีค้นหาห้อง ดูแผนที่ ภาพ 360° และแก้ปัญหา',
                      onTap: () => openGuide(context),
                    ),
                    _SettingRow(
                      icon: Icons.flag_outlined,
                      title: 'แจ้งข้อมูลไม่ถูกต้อง',
                      subtitle: 'แจ้งผู้ดูแลเมื่อพบข้อมูลห้อง ตำแหน่ง หรือเวลาไม่ตรง',
                      onTap: () => showReportSheet(context),
                    ),
                  ],
                ),
                const _Heading('เกี่ยวกับ'),
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
                    _SettingRow(
                      icon: _serverOk == false ? Icons.cloud_off_rounded : Icons.cloud_done_outlined,
                      title: 'การเชื่อมต่อข้อมูล',
                      subtitle: _checking
                          ? 'กำลังตรวจสอบ...'
                          : switch (_serverOk) {
                              true => 'เชื่อมต่อได้ปกติ',
                              false => 'เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ต',
                              null => 'แตะเพื่อตรวจสอบการเชื่อมต่อ',
                            },
                      subtitleColor: switch (_serverOk) {
                        true => AppColors.primary,
                        false => AppColors.danger,
                        null => null,
                      },
                      trailing: _checking
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                          : TextButton(onPressed: _checkServer, child: const Text('ตรวจสอบ')),
                      onTap: _checkServer,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: AppColors.tint, shape: BoxShape.circle),
                      child: Icon(Icons.domain_rounded, size: 18, color: AppColors.primary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'มหาวิทยาลัยเกษตรศาสตร์ วิทยาเขตกำแพงแสน',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// หัวข้อกลุ่มตั้งค่า (ตัวหนา) พร้อมข้อความเล็กทางขวาได้
class _Heading extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _Heading(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ),
          ?trailing,
        ],
      ),
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
        decoration: appCardDecoration(radius: 18),
        child: Row(
          children: [
            for (final (mode, label, icon) in _options)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => ThemeController.set(mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: mode == current ? AppColors.tint : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Column(
                      children: [
                        Icon(icon, size: 22, color: mode == current ? AppColors.primary : AppColors.muted),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: mode == current ? FontWeight.w800 : FontWeight.w500,
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

/// สลับขนาดตัวอักษร ปกติ / ใหญ่
class _SizeToggle extends StatelessWidget {
  final bool large;
  final ValueChanged<bool> onChanged;

  const _SizeToggle({required this.large, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool value) {
      final active = large == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1))] : null,
          ),
          child: Text(
            label,
            style: TextStyle(color: active ? AppColors.primary : AppColors.muted, fontSize: 12.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [option('ปกติ', false), option('ใหญ่', true)]),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: appCardDecoration(radius: 18).copyWith(
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 8, offset: const Offset(0, 2))],
      ),
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
  final Color? subtitleColor;
  final String? badge;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.badge,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(999)),
                          child: Text(badge!, style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: subtitleColor ?? AppColors.muted, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
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
