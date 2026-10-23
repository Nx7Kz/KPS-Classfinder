import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'api_client.dart';
import 'offline_cache.dart';
import 'open_status.dart';
import 'room_utils.dart';

class SyncProgress {
  final int done;
  final int total;
  final String label;

  const SyncProgress(this.done, this.total, this.label);

  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

class SyncResult {
  final int buildings;
  final int rooms;
  final int floorPlans;

  /// จำนวนรูปที่ดาวน์โหลดเก็บไว้ (0 ถ้าซิงค์เฉพาะข้อมูลตัวหนังสือ)
  final int images;

  /// รูปที่ดาวน์โหลดไม่สำเร็จ
  final int failedImages;

  const SyncResult({required this.buildings, required this.rooms, required this.floorPlans, required this.images, required this.failedImages});
}

/// ดึงข้อมูลทั้งหมดที่ใช้ดูออฟไลน์มาเก็บไว้ในเครื่อง: อาคาร ห้องทุกอาคาร แผนผังทุกชั้น วันปิดพิเศษ
/// และ (เมื่อ [images] = true) ไฟล์รูปแผนผังกับรูปปกอาคาร ภาพ 360° ไม่รวม เพราะไฟล์ใหญ่มาก
class OfflineSync {
  const OfflineSync._();

  static const staleAfter = Duration(hours: 24);

  /// ไม่ใช่ null ระหว่างกำลังซิงค์ (ให้หน้าตั้งค่าแสดงแถบความคืบหน้า)
  static final ValueNotifier<SyncProgress?> progress = ValueNotifier<SyncProgress?>(null);

  static bool get running => progress.value != null;

  /// ตัวจัดการแคชรูป (โฟลเดอร์ในเครื่อง) ใช้ตัวเดียวกับ CachedNetworkImage ที่แสดงรูปในแอป
  static CacheManager get imageCache => DefaultCacheManager();

  static Future<SyncResult> run({bool images = true}) async {
    if (running) throw const ApiException('กำลังซิงค์อยู่ รอสักครู่');
    progress.value = const SyncProgress(0, 0, 'กำลังตรวจสอบอาคาร...');
    try {
      final buildings = await Api.buildings();
      final plans = <FloorPlan>[];
      final imageUrls = <String>{};
      var rooms = 0;
      var floors = 0;

      // ขั้นที่ 1: ห้องของทุกอาคาร (รู้จำนวนชั้นทั้งหมดเพื่อคำนวณความคืบหน้า)
      final floorsByBuilding = <String, List<String>>{};
      for (var i = 0; i < buildings.length; i++) {
        final name = buildings[i]['name']?.toString() ?? '';
        progress.value = SyncProgress(i, buildings.length, 'ห้องใน$name');
        final list = await Api.roomsInBuilding(name);
        rooms += list.length;
        floorsByBuilding[name] = sortFloors(list.map(floorOf));
        floors += floorsByBuilding[name]!.length;
        final cover = buildings[i]['cover_image']?.toString();
        final planImage = buildings[i]['floor_plan_image']?.toString();
        if (cover != null && cover.isNotEmpty) {
          imageUrls.add(Api.assetUrl(cover));
        } else if (planImage != null && planImage.isNotEmpty) {
          imageUrls.add(Api.assetUrl(planImage));
        }
      }

      // ขั้นที่ 2: แผนผังทุกชั้น
      var done = 0;
      final total = floors;
      for (final entry in floorsByBuilding.entries) {
        for (final floor in entry.value) {
          progress.value = SyncProgress(done, total, 'แผนผัง ${entry.key} ${floorLabel(floor)}');
          try {
            final plan = await Api.floorPlan(entry.key, floor);
            if (plan != null) {
              plans.add(plan);
              imageUrls.add(plan.imageUrl);
            }
          } on ApiException catch (error) {
            if (error.isConnection) rethrow; // ชั้นนี้ไม่มีแผนผัง/ผิดพลาดชั่วคราวก็ข้ามได้ แต่ถ้าเน็ตหลุดให้หยุด
          }
          done++;
        }
      }

      await ClosureStore.refresh();

      // ขั้นที่ 3: ดาวน์โหลดไฟล์รูป
      var downloaded = 0;
      var failed = 0;
      if (images) {
        final urls = imageUrls.toList();
        for (var i = 0; i < urls.length; i++) {
          progress.value = SyncProgress(i, urls.length, 'ดาวน์โหลดรูป ${i + 1}/${urls.length}');
          try {
            await imageCache.downloadFile(urls[i]);
            downloaded++;
          } catch (_) {
            failed++;
          }
        }
      }

      await OfflineCache.markSynced(images: images ? downloaded : null);
      OfflineCache.offlineSince.value = null;
      return SyncResult(buildings: buildings.length, rooms: rooms, floorPlans: plans.length, images: downloaded, failedImages: failed);
    } finally {
      progress.value = null;
    }
  }

  /// เปิดแอปแล้วถ้าข้อมูลที่ซิงค์ไว้เก่ากว่า 24 ชั่วโมง ให้ซิงค์เงียบ ๆ เฉพาะข้อมูลตัวหนังสือ (ไม่โหลดรูป กันเปลืองเน็ต)
  /// ถ้าเชื่อมต่อไม่ได้ก็ข้าม ไม่แจ้งผู้ใช้
  static Future<void> autoIfStale() async {
    if (running) return;
    final last = await OfflineCache.lastSync();
    if (last != null && DateTime.now().difference(last) < staleAfter) return;
    try {
      await run(images: false);
    } catch (_) {
      // ไม่มีเน็ตหรือเซิร์ฟเวอร์ไม่ตอบ: ใช้แคชเดิม
    }
  }

  static Future<void> clearAll() async {
    await OfflineCache.clearAll();
    try {
      await imageCache.emptyCache();
    } catch (_) {}
  }
}

