# ขึ้นระบบบน VPS (Ubuntu 24.04 + Docker)

โดเมน `kps-classfinder.tech` ต้องมี A record ชี้มาที่ IP ของ VPS ก่อน (ตรวจ: `nslookup kps-classfinder.tech`)

## 1. เข้าเครื่อง

hPanel > VPS > **Web console** หรือ `ssh root@<IP>`

## 2. ตั้งค่าเครื่อง (ครั้งเดียว)

```bash
apt update && apt upgrade -y
# swap 2GB กันหน่วยความจำเต็มตอน build
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
# ไฟร์วอลล์: เปิดเฉพาะ SSH, HTTP, HTTPS
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable
docker --version && docker compose version   # ถ้าไม่ขึ้น ให้ติดตั้ง: curl -fsSL https://get.docker.com | sh
```

## 3. ดึงโค้ด

```bash
cd /opt && git clone https://github.com/Nx7Kz/KPS-Classfinder.git
cd KPS-Classfinder/kps_backend
mkdir -p public/panoramas public/floorplans public/covers public/tour-images backup/backups
```

## 4. สร้าง .env

```bash
cp .env.example .env
nano .env
```

เติม `MYSQL_ROOT_PASSWORD`, `SESSION_SECRET` (สุ่มด้วย `openssl rand -hex 24`) และ `ADMIN_PASSWORD` (ยาว ห้ามใช้รหัสเดียวกับที่อื่น) จดไว้ในที่ปลอดภัย

## 5. เปิดระบบ

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f backend   # ดู log (Ctrl+C ออก)
```

เปิด https://kps-classfinder.tech (ใบรับรอง HTTPS ออกให้เองภายในหนึ่งนาที)

## 6. ย้ายข้อมูลจากเครื่องเดิม

1. เครื่องเดิม: แดชบอร์ด > ตั้งค่า > สำรองข้อมูล > สร้างไฟล์สำรอง แล้วดาวน์โหลด `.zip`
2. ส่งไฟล์ขึ้น VPS (รันบนเครื่อง Windows ของคุณ ในโฟลเดอร์ที่ดาวน์โหลด):
   ```powershell
   scp .\kps_backup_xxxx.zip root@<IP>:/opt/KPS-Classfinder/kps_backend/backup/backups/
   ```
3. VPS: ล็อกอินด้วย `ADMIN_USERNAME`/`ADMIN_PASSWORD` > สำรองข้อมูล > เลือกไฟล์ > กู้คืน — บัญชีผู้ดูแลทั้งหมดจะมาจากไฟล์สำรอง (ใช้รหัสผ่านเดิมจากเครื่องเก่า)

## 7. ใช้งานประจำ

```bash
cd /opt/KPS-Classfinder/kps_backend
git pull && docker compose -f docker-compose.prod.yml up -d --build   # อัปเดตโค้ด
docker compose -f docker-compose.prod.yml ps                          # ดูสถานะ
```

- ไฟล์สำรองอยู่ที่ `backup/backups/` — ควรดาวน์โหลดเก็บไว้นอกเครื่องเป็นระยะ
- ต้องการเปิด phpMyAdmin ชั่วคราว: อย่าเปิดพอร์ตสู่อินเทอร์เน็ต ใช้ SSH tunnel แทน
