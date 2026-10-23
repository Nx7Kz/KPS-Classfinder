import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'report_sheet.dart';

Future<void> openGuide(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen()));
}

/// หัวข้อวิธีใช้งานและคำถามที่พบบ่อย เขียนให้ตรงกับฟีเจอร์ที่แอปมีอยู่จริงตอนนี้
const _howTo = [
  (
    Icons.search_rounded,
    'ค้นหาห้อง',
    'พิมพ์รหัสห้อง ชื่ออาคาร หรือประเภทห้องที่หน้าค้นหา เช่น LH3-201, 80 ปี, ห้องบรรยาย ผลลัพธ์จะขึ้นระหว่างพิมพ์ '
        'แตะชิปใต้ช่องค้นหาเพื่อค้นด้วยชื่ออาคารหรือประเภทห้องได้ทันที ถ้าพบห้องเดียวแล้วกด Enter ระบบจะเปิดรายละเอียดห้องให้เลย',
  ),
  (
    Icons.schedule_rounded,
    'อ่านป้ายสถานะ',
    'เปิดอยู่ (เขียว) = อยู่ในเวลาทำการตามเวลาไทย • ปิดอยู่ (เทา) = นอกเวลาทำการ และบอกเวลาเปิดครั้งถัดไป • '
        'ปิดปรับปรุง (ส้ม) = ห้องปิดซ่อม • ปิดทำการ = วันหยุดหรือวันปิดพิเศษ ห้องหรืออาคารที่ไม่มีป้ายคือผู้ดูแลยังไม่ได้ตั้งเวลาทำการ',
  ),
  (
    Icons.explore_outlined,
    'ดูตำแหน่งบนแผนที่',
    'เปิดแท็บแผนที่ เลือกอาคาร เลือกชั้น แล้วแตะหมุดเพื่อดูห้อง ซูมด้วยการบีบนิ้วหรือปุ่ม + / − ปุ่มเต็มจอจะขยายแผนผังให้ใหญ่ขึ้น '
        'หมุดสีส้มคือห้องที่ปิดปรับปรุง หมุดที่มีวงกลม 360° คือห้องที่มีภาพ 360° ปรับให้แสดงชื่อห้องตลอดเวลาหรือใช้ตัวอักษรใหญ่ได้ที่ ตั้งค่า > การแสดงผล',
  ),
  (
    Icons.threesixty_rounded,
    'ดูภาพ 360°',
    'ลากนิ้วเพื่อหมุนมอง บีบนิ้วเพื่อซูม แตะจุดเชื่อมในภาพ (ลูกศร ประตู บันได) เพื่อเดินไปมุมถัดไป ถ้าห้องมีหลายภาพให้เลือกมุมจากแถบด้านล่าง '
        'ปุ่มด้านขวาใช้ซูมและกลับมุมเริ่มต้น บนมือถือเปิดโหมดหมุนภาพตามการเอียงเครื่องได้',
  ),
  (
    Icons.notifications_none_rounded,
    'ประกาศและการปิดทำการ',
    'กดกระดิ่งที่แถบบนหน้าค้นหาเพื่อดูวันปิดทำการพิเศษที่กำลังจะมาถึงและอาคารที่มีห้องปิดปรับปรุง แตะประกาศเพื่อเปิดอาคารนั้น',
  ),
  (
    Icons.star_outline_rounded,
    'ห้องโปรดและประวัติ',
    'กดรูปดาวในหน้ารายละเอียดห้องเพื่อบันทึกเป็นห้องโปรด ห้องที่เพิ่งดูจะขึ้นในหน้าค้นหาเพื่อกลับมาเปิดซ้ำได้เร็ว '
        'ข้อมูลทั้งสองเก็บไว้ในเครื่องนี้ ล้างได้ที่ ตั้งค่า > ข้อมูลในเครื่อง',
  ),
];

const _faq = [
  (
    'ทำไมห้องขึ้นว่า "ปิดอยู่" ทั้งที่ฉันเห็นว่าเปิด?',
    'ป้ายสถานะคำนวณจากเวลาทำการที่ผู้ดูแลตั้งไว้ในระบบ ถ้าเวลาจริงต่างจากที่แสดง กด "แจ้งข้อมูลไม่ถูกต้อง" ในหน้ารายละเอียดห้องเพื่อให้ผู้ดูแลแก้ไข',
  ),
  (
    'ทำไมไม่เห็นหมุดของห้องบนแผนที่?',
    'ห้องนั้นอาจยังไม่ได้ปักหมุดบนแผนผังชั้น ยังดูรายชื่อห้องของชั้นนั้นได้จากปุ่ม "รายการห้อง" ในหน้าแผนที่',
  ),
  (
    'ภาพ 360° โหลดช้า',
    'ภาพ 360° มีความละเอียดสูงและไฟล์ใหญ่ แนะนำให้เชื่อมต่อ Wi-Fi และรอสักครู่ให้ภาพโหลดเสร็จ',
  ),
  (
    'ข้อมูลไม่ขึ้นหรือแอปเชื่อมต่อไม่ได้',
    'ตรวจสอบอินเทอร์เน็ตของเครื่อง จากนั้นเปิด ตั้งค่า > การเชื่อมต่อข้อมูล แล้วกด "ตรวจสอบ" ถ้ายังไม่ได้ ลองใหม่ภายหลังหรือแจ้งผู้ดูแล',
  ),
  (
    'พบข้อมูลห้องหรือตำแหน่งไม่ตรงความจริง ทำอย่างไร?',
    'เปิดห้องนั้น เลื่อนลงล่างสุดของหน้ารายละเอียด แล้วกด "ข้อมูลห้องนี้ไม่ตรง?" เลือกหัวข้อและอธิบายสั้น ๆ ผู้ดูแลจะได้รับเรื่องทันที',
  ),
];

/// คู่มือการใช้งานและคำถามที่พบบ่อย (ไม่ต้องใช้อินเทอร์เน็ต)
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'ย้อนกลับ',
                    icon: Icon(Icons.arrow_back_rounded, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text('คู่มือการใช้งาน', style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.fill,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ใช้แอปให้คล่อง', style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text(
                                  'แตะหัวข้อด้านล่างเพื่อดูวิธีใช้ค้นหาห้อง ดูแผนที่ ภาพ 360° และแก้ปัญหาที่พบบ่อย',
                                  style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _GuideHeading('วิธีใช้งาน'),
                    for (final (icon, title, body) in _howTo) _GuideTile(icon: icon, title: title, body: body),
                    const _GuideHeading('คำถามที่พบบ่อย'),
                    for (final (question, answer) in _faq) _GuideTile(icon: Icons.help_outline_rounded, title: question, body: answer),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: appCardDecoration(radius: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ไม่พบคำตอบที่ต้องการ?', style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text('ส่งข้อความถึงผู้ดูแลได้โดยตรง', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 46), shape: const StadiumBorder()),
                              onPressed: () => showReportSheet(context),
                              icon: const Icon(Icons.flag_outlined, size: 19),
                              label: const Text('แจ้งข้อมูลไม่ถูกต้อง / ส่งข้อความ'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideHeading extends StatelessWidget {
  final String title;

  const _GuideHeading(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(title, style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
    );
  }
}

/// การ์ดหัวข้อที่แตะเพื่อกางอ่านเนื้อหา
class _GuideTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _GuideTile({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: appCardDecoration(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.muted,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          title: Text(title, style: TextStyle(color: AppColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3)),
          children: [Text(body, style: TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.55))],
        ),
      ),
    );
  }
}
