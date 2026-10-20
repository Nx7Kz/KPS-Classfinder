# สำรองข้อมูล (Backup)

สำรองฐานข้อมูล MySQL (`kps_classfinder`) และไฟล์ที่อัปโหลดผ่านแดชบอร์ด (ผังชั้น, รูปปก,
ภาพ 360°, ภาพเดินชมอาคาร) รวมเป็นไฟล์ `.zip` เดียว เก็บไว้ในเครื่อง — ทำงานผ่าน Docker
container ที่รันอยู่แล้ว ไม่ต้องติดตั้งอะไรเพิ่ม (ใช้ PowerShell + Docker Desktop ที่มีอยู่แล้ว)

## สำรองข้อมูล

ต้องเปิด `docker compose up -d` ที่ `kps_backend` ไว้ก่อน แล้วรัน:

```powershell
cd kps_backend\backup
.\backup.ps1
```

ไฟล์จะถูกเก็บไว้ที่ `kps_backend\backup\backups\kps-backup_<วันที่-เวลา>.zip`
(เก็บอัตโนมัติ 14 ชุดล่าสุด ชุดเก่ากว่านั้นจะถูกลบทิ้ง)

เก็บไปที่โฟลเดอร์อื่น (เช่น external drive หรือ cloud sync):

```powershell
.\backup.ps1 -OutDir "D:\Backups\KPS" -Keep 30
```

## กู้คืนข้อมูล

**คำเตือน:** จะเขียนทับฐานข้อมูลและไฟล์อัปโหลดปัจจุบันทั้งหมด

```powershell
cd kps_backend\backup
.\restore.ps1 -ZipPath .\backups\kps-backup_2026-10-20_153000.zip
```

## ตั้งให้ทำอัตโนมัติทุกวัน (Windows Task Scheduler)

1. เปิด Task Scheduler → Create Task
2. Trigger: Daily เวลาที่เครื่องเปิดอยู่แน่ๆ (เช่น ตอนเที่ยง)
3. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "D:\KPS_Project\kps_backend\backup\backup.ps1"`
4. ติ๊ก "Run whether user is logged on or not" ถ้าอยากให้ทำงานแม้ไม่ได้ล็อกอิน

## หมายเหตุ

- ไฟล์ backup (`backups/`) **ไม่ขึ้น git** (ไฟล์ใหญ่ + มีข้อมูลผู้ใช้) — อยู่ในเครื่องเท่านั้น
  ถ้าต้องการความปลอดภัยสูงขึ้นให้ตั้ง `-OutDir` ไปยัง external drive หรือโฟลเดอร์ที่ sync ขึ้น cloud เอง
- สคริปต์ dump ด้วย user `root` (ไม่มีรหัสผ่าน) ตรงกับการตั้งค่า `MYSQL_ALLOW_EMPTY_PASSWORD` ใน
  `docker-compose.yml` ของโปรเจกต์นี้ — ถ้าเปลี่ยนไปใช้ hosting จริงที่มีรหัสผ่าน ต้องแก้คำสั่ง mysqldump/mysql
  ในสคริปต์ให้ใส่ `-p<รหัสผ่าน>` ด้วย
