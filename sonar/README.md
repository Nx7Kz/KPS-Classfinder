# ตรวจคุณภาพโค้ดด้วย SonarQube

SonarQube อ่านโค้ด backend (Express) และแดชบอร์ด admin (vanilla JS) แล้วรายงาน Bugs, Vulnerabilities,
Security Hotspots, Code Smells และโค้ดซ้ำ พร้อมเกรด A–E — รันในเครื่องผ่าน Docker แยกจากระบบแอปทั้งหมด

| ไฟล์ | หน้าที่ |
|---|---|
| `docker-compose.yml` | SonarQube server + ฐานข้อมูลของ SonarQube เอง (พอร์ต 9000) |
| `../sonar-project.properties` | ตั้งค่าการตรวจ: โฟลเดอร์ที่ตรวจ / ไฟล์ที่ข้าม |
| `sonar_scan.py` | ตั้งค่าครั้งแรกให้อัตโนมัติ + รัน scanner + สรุปผลบนหน้าจอ |
| `sonar_report.py` | ดึงผลตรวจผ่าน Web API แล้วสร้างรายงาน PDF ภาษาไทย |
| `webhook-sample.json` | ตัวอย่าง JSON ที่ SonarQube ส่งออกทาง webhook เมื่อตรวจเสร็จ (Quality Gate ผ่าน/ไม่ผ่าน) |
| `reports/` | รายงาน PDF ที่สร้างแล้ว |
| `.env` | รหัส admin + token ของ SonarQube (สร้างอัตโนมัติ **ไม่ขึ้น git**) |

## วิธีใช้

ต้องมี Docker Desktop และ Python 3 (ไม่ต้อง pip install อะไร)

```bash
# 1. เปิด SonarQube (ครั้งแรกดาวน์โหลด ~1 GB และรอ 1–2 นาที)
docker compose -f sonar/docker-compose.yml up -d

# 2. ตรวจโค้ด (ครั้งแรกจะเปลี่ยนรหัส admin, สร้างโปรเจกต์และ token ให้เอง)
python sonar/sonar_scan.py

# 3. สร้างรายงาน PDF -> sonar/reports/sonar-report-<วันที่>.pdf
python sonar/sonar_report.py

# 4. ใช้เสร็จแล้วปิด (ผลตรวจยังอยู่)
docker compose -f sonar/docker-compose.yml stop
```

ดูผลละเอียดบนเว็บ: http://localhost:9000/dashboard?id=kps-classfinder
(ล็อกอิน `admin` รหัสผ่านอยู่ใน `sonar/.env` บรรทัด `SONAR_ADMIN_PASSWORD`)

## Webhook

ให้ SonarQube ส่งผลตรวจ (JSON แบบ `webhook-sample.json`) ไปยังระบบอื่นทุกครั้งที่ตรวจเสร็จ เช่น แจ้งเตือนทีม:

```bash
SONAR_WEBHOOK_URL=https://example.com/sonar-hook python sonar/sonar_scan.py
```

URL ที่อยู่ในเครื่องเดียวกันให้ใช้ `http://host.docker.internal:<พอร์ต>/...` (SonarQube รันใน Docker)

## หมายเหตุ

- ใช้ RAM ประมาณ 2–3 GB ตอนเปิด
- **ตรวจเฉพาะ backend (`kps_backend/server.js`) และแดชบอร์ด admin (`kps_backend/public`)** — แอปมือถือ
  (Flutter/Dart) ยังไม่ได้ตรวจ เพราะ SonarQube Community Edition ยังไม่รองรับภาษา Dart โดยตรง
  (ต้องใช้ปลั๊กอินเสริมอย่าง `sonar-flutter` ถ้าอยากเพิ่มทีหลัง)
- **ยังไม่มี coverage:** backend ยังไม่มีชุดทดสอบอัตโนมัติ (สคริปต์ `test` ใน `kps_backend/package.json`
  เป็นแค่ placeholder) จึงยังไม่มีผลทดสอบส่งเข้า SonarQube — ตรวจ Bug/Vulnerability/Code Smell ได้ตามปกติ
  ถ้าเพิ่มชุดทดสอบทีหลัง ต่อ coverage ได้ด้วย `sonar.javascript.lcov.reportPaths` ใน `sonar-project.properties`
- ไฟล์ที่ผู้ใช้อัปโหลดผ่านแดชบอร์ด (ผังชั้น, รูปปก, ภาพ 360°) ไม่ถูกตรวจ (ข้ามไว้ใน `sonar.exclusions`)
- ถ้าลบ volume ของ SonarQube (`docker compose -f sonar/docker-compose.yml down -v`) ให้ลบ `sonar/.env` ด้วย แล้วรัน `sonar_scan.py` ใหม่
- ถ้าเปิดโปรเจกต์ `pos-stock-moo-kratha` ที่ใช้ SonarQube เหมือนกันพร้อมกัน จะชนพอร์ต 9000 — ปิดอีกฝั่งก่อน
  (หรือเปลี่ยนพอร์ตในไฟล์นี้)
