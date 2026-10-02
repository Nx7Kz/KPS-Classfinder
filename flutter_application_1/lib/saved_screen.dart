import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'room_detail_screen.dart';
import 'room_store.dart';
import 'widgets.dart';

/// แท็บ "บันทึก": ห้องโปรดและห้องที่ดูล่าสุด
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<Map<String, dynamic>> _favorites = const [];
  List<Map<String, dynamic>> _recents = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    RoomStore.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    RoomStore.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final favorites = await RoomStore.loadFavorites();
    final recents = await RoomStore.loadRecents();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _recents = recents;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // อ่านจากเครื่องเสร็จในเสี้ยววินาที แสดงว่างไว้ก่อนเพื่อไม่ให้มีอะไรกะพริบ
    if (!_loaded) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const PageHeader(title: 'บันทึก', subtitle: 'ห้องที่คุณบันทึกไว้และดูล่าสุด'),
        if (_favorites.isEmpty && _recents.isEmpty)
          const SizedBox(
            height: 420,
            child: StateView(
              icon: Icons.bookmark_border_rounded,
              title: 'ยังไม่มีห้องที่บันทึกไว้',
              message: 'กดไอคอนดาวในหน้ารายละเอียดห้อง เพื่อเก็บห้องที่ใช้บ่อยไว้ที่นี่',
            ),
          ),
        if (_favorites.isNotEmpty) ...[
          SectionTitle('ห้องโปรด (${_favorites.length})'),
          for (final room in _favorites)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RoomTile(
                room: room,
                icon: Icons.star_rounded,
                onTap: () => openRoom(context, room),
                trailing: IconButton(
                  tooltip: 'นำออกจากรายการโปรด',
                  icon: Icon(Icons.bookmark_remove_outlined, color: AppColors.muted),
                  onPressed: () async {
                    await RoomStore.toggleFavorite(room);
                    if (context.mounted) showAppSnack(context, 'นำออกจากรายการโปรดแล้ว');
                  },
                ),
              ),
            ),
        ],
        if (_recents.isNotEmpty) ...[
          SectionTitle(
            'ดูล่าสุด',
            trailing: TextButton(
              onPressed: RoomStore.clearRecents,
              child: Text('ล้างประวัติ', style: TextStyle(color: AppColors.muted)),
            ),
          ),
          for (final room in _recents)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RoomTile(
                room: room,
                icon: Icons.history_rounded,
                onTap: () => openRoom(context, room),
              ),
            ),
        ],
      ],
    );
  }
}
