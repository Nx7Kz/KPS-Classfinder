import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_theme.dart';
import 'room_detail_screen.dart';
import 'room_list_screen.dart';
import 'room_store.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _suggestions = const [];
  bool _isLoadingSuggestions = false;
  String? _exampleRoomCode;
  List<Map<String, dynamic>> _favorites = const [];
  List<Map<String, dynamic>> _recents = const [];

  @override
  void initState() {
    super.initState();
    _loadExampleRoomCode();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final favorites = await RoomStore.loadFavorites();
    final recents = await RoomStore.loadRecents();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _recents = recents;
    });
  }

  Future<void> _loadExampleRoomCode() async {
    try {
      final url = ApiConfig.endpoint('api/rooms/sample');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['room_code'] == null) return;

      if (!mounted) return;
      setState(() => _exampleRoomCode = decoded['room_code'].toString());
    } catch (_) {
      // ไม่มีตัวอย่างก็ไม่เป็นไร แสดงข้อความทั่วไปแทน
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRoomMatches(String query) async {
    final url = ApiConfig.endpoint('api/rooms/search').replace(
      queryParameters: {'q': query},
    );
    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('ค้นหาห้องเรียนไม่สำเร็จ');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('รูปแบบข้อมูลห้องเรียนไม่ถูกต้อง');
    }

    return decoded.map((room) {
      if (room is! Map) {
        throw const FormatException('รูปแบบข้อมูลห้องเรียนไม่ถูกต้อง');
      }
      return Map<String, dynamic>.from(room);
    }).toList();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _suggestions = const [];
        _isLoadingSuggestions = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isLoadingSuggestions = true);

      try {
        final results = await _fetchRoomMatches(query);
        if (!mounted || _searchController.text.trim() != query) return;
        setState(() {
          _suggestions = results;
          _isLoadingSuggestions = false;
        });
      } catch (_) {
        if (!mounted || _searchController.text.trim() != query) return;
        setState(() {
          _suggestions = const [];
          _isLoadingSuggestions = false;
        });
      }
    });
  }

  Future<void> searchRoom(String roomCode) async {
    final query = roomCode.trim();
    if (query.isEmpty) return;

    try {
      final matches = await _fetchRoomMatches(query);
      if (!mounted) return;

      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบห้องเรียนนี้ในระบบ')),
        );
      } else if (matches.length == 1) {
        _openRoomDetail(matches.single);
      } else {
        _showRoomPicker(matches);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการค้นหา: $error')),
      );
    }
  }

  Future<void> _openRoomDetail(Map<String, dynamic> room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
    );
    _loadHistory();
  }

  void _showRoomPicker(List<Map<String, dynamic>> matches) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('เลือกห้องเรียน', style: TextStyle(fontWeight: FontWeight.w700)),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Material(
            type: MaterialType.transparency,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final room = matches[index];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.blueTint,
                    child: Icon(Icons.meeting_room_outlined, color: AppColors.primary),
                  ),
                  title: Text(room['room_code']?.toString() ?? '-'),
                  subtitle: Text(
                    '${room['building_name'] ?? '-'} • ชั้น ${room['floor'] ?? '-'}',
                  ),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _openRoomDetail(room);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    if (_isLoadingSuggestions) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: appCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
          itemBuilder: (context, index) {
            final room = _suggestions[index];
            return ListTile(
              dense: true,
              leading: const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.blueTint,
                child: Icon(Icons.search_rounded, color: AppColors.primary, size: 18),
              ),
              title: Text(
                room['room_code']?.toString() ?? '-',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              subtitle: Text(
                '${room['building_name'] ?? '-'} • ชั้น ${room['floor'] ?? '-'}',
                style: const TextStyle(color: AppColors.muted),
              ),
              onTap: () {
                _searchController.text = room['room_code']?.toString() ?? '';
                _onSearchChanged('');
                _searchFocusNode.unfocus();
                _openRoomDetail(room);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ค้นหาห้องเรียน',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _exampleRoomCode == null
                    ? 'พิมพ์รหัสห้องเพื่อค้นหาแบบรวดเร็ว'
                    : 'พิมพ์รหัสห้อง เช่น $_exampleRoomCode เพื่อค้นหาแบบรวดเร็ว',
                style: const TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  onSubmitted: searchRoom,
                  style: const TextStyle(color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'ค้นหาห้องเรียน',
                    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppColors.muted),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onTapOutside: (_) => _searchFocusNode.unfocus(),
                  onEditingComplete: () => setState(() {}),
                ),
              ),
              _buildSuggestions(),
              if (_searchController.text.trim().isEmpty) ...[
                _buildFavoritesSection(),
                _buildRecentsSection(),
              ],
              const SizedBox(height: 32),
              const Text(
                'ค้นหาตามอาคารเรียน',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildCategoryChip(
                    Icons.domain_rounded,
                    'อาคารเรียนรวม 3 (ศร.3)',
                    AppColors.primary,
                    AppColors.blueTint,
                  ),
                  _buildCategoryChip(
                    Icons.apartment_rounded,
                    'อาคารเรียน 80 ปี',
                    AppColors.accent,
                    AppColors.goldTint,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesSection() {
    if (_favorites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: appCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bookmark_rounded, color: AppColors.accent, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'ห้องที่บันทึกไว้',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final room in _favorites) _buildSavedRoomTile(room),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSavedRoomTile(Map<String, dynamic> room) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openRoomDetail(room),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.meeting_room_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room['room_code']?.toString() ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13),
                    ),
                    Text(
                      room['building_name']?.toString() ?? '-',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ดูรายละเอียด',
                      style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentsSection() {
    if (_recents.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ค้นหาล่าสุด',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            TextButton(
              onPressed: () async {
                await RoomStore.clearRecents();
                _loadHistory();
              },
              child: const Text('ล้างประวัติ', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          ],
        ),
        Container(
          decoration: appCardDecoration(),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _recents.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
              itemBuilder: (context, index) {
                final room = _recents[index];
                return ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.blueTint,
                    child: Icon(Icons.history_rounded, color: AppColors.primary, size: 18),
                  ),
                  title: Text(
                    room['room_code']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                  subtitle: Text(
                    '${room['building_name'] ?? '-'} • ชั้น ${room['floor'] ?? '-'}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  onTap: () => _openRoomDetail(room),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(
    IconData icon,
    String buildingName,
    Color iconColor,
    Color tintColor,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoomListScreen(buildingName: buildingName),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line),
          boxShadow: const [
            BoxShadow(color: Color(0x120F172A), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: tintColor,
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 10),
            Text(
              buildingName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
