import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'room_detail_screen.dart';
import 'room_list_screen.dart';
import 'room_store.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  List<Map<String, dynamic>> _results = const [];
  bool _isSearching = false;
  Object? _searchError;

  List<Map<String, dynamic>> _recents = const [];
  late Future<List<Map<String, dynamic>>> _buildingsFuture;

  @override
  void initState() {
    super.initState();
    _buildingsFuture = Api.buildings();
    RoomStore.revision.addListener(_loadRecents);
    _loadRecents();
  }

  @override
  void dispose() {
    RoomStore.revision.removeListener(_loadRecents);
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final recents = await RoomStore.loadRecents();
    if (!mounted) return;
    setState(() => _recents = recents);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _isSearching = false;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _query = query;
      _isSearching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await Api.searchRooms(query);
      if (!mounted || _query != query) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || _query != query) return;
      setState(() {
        _results = const [];
        _isSearching = false;
        _searchError = error;
      });
    }
  }

  /// กด Enter: ถ้าเจอห้องเดียวเปิดรายละเอียดเลย ไม่งั้นค้างรายการให้เลือก
  Future<void> _submit(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    setState(() {
      _query = query;
      _isSearching = true;
      _searchError = null;
    });
    await _runSearch(query);
    if (!mounted || _results.length != 1) return;
    _focusNode.unfocus();
    openRoom(context, _results.single);
  }

  void _retryBuildings() {
    setState(() => _buildingsFuture = Api.buildings());
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _focusNode.unfocus(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Row(
            children: [
              const IconBadge(Icons.school_rounded, size: 34),
              const SizedBox(width: 10),
              Text(
                'KPS ClassFinder',
                style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const PageHeader(
            title: 'ค้นหาห้องเรียน',
            subtitle: 'พิมพ์รหัสห้อง เช่น LH3-201 แล้วดูตำแหน่งบนแผนที่ได้ทันที',
          ),
          const SizedBox(height: 18),
          AppSearchField(
            controller: _controller,
            focusNode: _focusNode,
            hint: 'รหัสห้องเรียน',
            onChanged: _onChanged,
            onSubmitted: _submit,
          ),
          if (searching)
            ..._buildResults()
          else ...[
            ..._buildRecents(),
            ..._buildBuildingShortcuts(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildResults() {
    if (_isSearching && _results.isEmpty) {
      return const [Padding(padding: EdgeInsets.only(top: 48), child: LoadingView())];
    }

    if (_searchError != null) {
      return [
        SizedBox(
          height: 260,
          child: StateView.error(_searchError!, onRetry: () => _runSearch(_query)),
        ),
      ];
    }

    if (_results.isEmpty) {
      return [
        SizedBox(
          height: 240,
          child: StateView(
            icon: Icons.search_off_rounded,
            title: 'ไม่พบห้อง "$_query"',
            message: 'ลองตรวจสอบตัวสะกด หรือค้นหาด้วยบางส่วนของรหัสห้อง',
          ),
        ),
      ];
    }

    return [
      SectionTitle('ผลการค้นหา (${_results.length})'),
      for (final room in _results)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RoomTile(
            room: room,
            onTap: () {
              _focusNode.unfocus();
              openRoom(context, room);
            },
          ),
        ),
    ];
  }

  List<Widget> _buildRecents() {
    if (_recents.isEmpty) return const [];

    return [
      SectionTitle(
        'ดูล่าสุด',
        trailing: TextButton(
          onPressed: RoomStore.clearRecents,
          child: Text('ล้าง', style: TextStyle(color: AppColors.muted)),
        ),
      ),
      for (final room in _recents.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RoomTile(
            room: room,
            icon: Icons.history_rounded,
            onTap: () => openRoom(context, room),
          ),
        ),
    ];
  }

  List<Widget> _buildBuildingShortcuts() {
    return [
      const SectionTitle('เลือกจากอาคาร'),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _buildingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: LoadingView());
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 240,
              child: StateView.error(snapshot.error!, onRetry: _retryBuildings),
            );
          }
          final buildings = snapshot.data ?? const [];
          if (buildings.isEmpty) {
            return const SizedBox(
              height: 200,
              child: StateView(
                icon: Icons.apartment_outlined,
                title: 'ยังไม่มีอาคารในระบบ',
                message: 'รอผู้ดูแลเพิ่มข้อมูลอาคาร',
              ),
            );
          }
          return Column(
            children: [
              for (final building in buildings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BuildingShortcut(building: building),
                ),
            ],
          );
        },
      ),
    ];
  }
}

class _BuildingShortcut extends StatelessWidget {
  final Map<String, dynamic> building;

  const _BuildingShortcut({required this.building});

  @override
  Widget build(BuildContext context) {
    final name = building['name']?.toString() ?? '-';
    final roomCount = building['room_count']?.toString() ?? '0';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomListScreen(buildingName: name)),
        ),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: appCardDecoration(),
          child: Row(
            children: [
              const IconBadge(Icons.apartment_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text('$roomCount ห้อง', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
