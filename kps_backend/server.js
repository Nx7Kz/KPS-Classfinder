const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const session = require('express-session');
const bcrypt = require('bcryptjs');
const rateLimit = require('express-rate-limit');

const app = express();
const port = 3000;

app.set('trust proxy', 1);
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

// 🌟 ระบบเข้าสู่ระบบสำหรับ Admin Dashboard 🌟
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD_HASH
    || bcrypt.hashSync(process.env.ADMIN_PASSWORD || 'admin1234', 10);

app.use(session({
    secret: process.env.SESSION_SECRET || 'kps-classfinder-dev-secret',
    resave: false,
    saveUninitialized: false,
    cookie: {
        httpOnly: true,
        maxAge: 8 * 60 * 60 * 1000, // 8 ชั่วโมง
    },
}));

function requireAdmin(req, res, next) {
    if (req.session && req.session.isAdmin) {
        return next();
    }
    return res.status(401).json({ error: 'กรุณาเข้าสู่ระบบก่อนทำรายการนี้' });
}

// 🌟 จำกัดจำนวนครั้งที่ล็อกอินผิดได้ กันคนสุ่มรหัสผ่าน (brute force) 🌟
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 นาที
    max: 5,
    standardHeaders: true,
    legacyHeaders: false,
    skipSuccessfulRequests: true, // นับเฉพาะครั้งที่ล็อกอินผิด ไม่นับครั้งที่สำเร็จ
    message: { error: 'ลองเข้าสู่ระบบผิดหลายครั้งเกินไป กรุณาลองใหม่อีกครั้งในอีก 15 นาที' },
});

app.post('/api/login', loginLimiter, (req, res) => {
    const { username, password } = req.body || {};

    if (
        typeof username !== 'string' ||
        typeof password !== 'string' ||
        username !== ADMIN_USERNAME ||
        !bcrypt.compareSync(password, ADMIN_PASSWORD_HASH)
    ) {
        return res.status(401).json({ error: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });
    }

    req.session.isAdmin = true;
    res.json({ message: 'เข้าสู่ระบบสำเร็จ' });
});

app.post('/api/logout', (req, res) => {
    req.session.destroy(() => {
        res.json({ message: 'ออกจากระบบแล้ว' });
    });
});

app.get('/api/session', (req, res) => {
    res.json({ isAdmin: Boolean(req.session && req.session.isAdmin) });
});

// 🌟 สั่งให้ Express เปิดใช้งานไฟล์เว็บจากโฟลเดอร์ public 🌟
app.use(express.static('public'));

// 1. ตั้งค่าการเชื่อมต่อฐานข้อมูล MySQL 
const db = mysql.createConnection({
    host: 'db',        // เปลี่ยนตรงนี้จาก 'localhost' เป็น 'db'
    user: 'root',
    password: '',
    database: 'kps_classfinder'
});

// ตรวจสอบว่าเชื่อมต่อฐานข้อมูลสำเร็จไหม
db.connect((err) => {
    if (err) {
        console.error('❌ เชื่อมต่อฐานข้อมูลไม่สำเร็จ:', err);
        return;
    }
    console.log('✅ เชื่อมต่อฐานข้อมูล MySQL สำเร็จแล้ว!');
});

// 2. สร้าง API สำหรับดึงห้องเรียนตัวอย่าง 1 ห้อง (ไว้ใช้แสดงคำแนะนำการค้นหา)
app.get('/api/rooms/sample', (req, res) => {
    const sql = 'SELECT room_code FROM rooms ORDER BY RAND() LIMIT 1';

    db.query(sql, (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        if (results.length === 0) {
            return res.status(404).json({ message: 'ไม่พบห้องเรียนในระบบ' });
        }
        res.json(results[0]);
    });
});

// 3. สร้าง API สำหรับค้นหาห้องเรียน
app.get('/api/rooms/search', (req, res) => {
    const query = typeof req.query.q === 'string' ? req.query.q.trim() : '';

    if (!query) {
        return res.json([]);
    }

    const sql = `
        SELECT id, room_code, building_name, floor
        FROM rooms
        WHERE room_code LIKE ?
        ORDER BY building_name, floor, room_code
        LIMIT 20
    `;

    db.query(sql, [`%${query}%`], (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        res.json(results);
    });
});

app.get('/api/search/:room', (req, res) => {
    const roomCode = req.params.room;
    
    // คำสั่ง SQL ดึงข้อมูลห้องที่ตรงกับเลขที่ส่งมา
    const sql = "SELECT * FROM rooms WHERE room_code = ?";
    
    db.query(sql, [roomCode], (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        
        // ถ้าค้นหาไม่เจอ (ไม่มีข้อมูลในตาราง)
        if (results.length === 0) {
            return res.status(404).json({ message: "ไม่พบห้องเรียนนี้" });
        }
        
        // ถ้าเจอ ให้ส่งข้อมูลกลับไป
        res.json(results[0]); 
    });
});

// 4. 🌟 เพิ่ม API สำหรับดึงข้อมูลห้องทั้งหมดในอาคารที่เลือก 🌟
app.get('/api/building/:name', (req, res) => {
    const buildingName = req.params.name;
    
    // คำสั่ง SQL ดึงข้อมูลห้องทั้งหมดที่ชื่อตึกตรงกับที่ส่งมา
    const sql = "SELECT * FROM rooms WHERE building_name = ?";
    
    db.query(sql, [buildingName], (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        
        // ส่งข้อมูลกลับไปเป็น Array (รายการห้องทั้งหมด)
        res.json(results); 
    });
});

// ==========================================
// 🌟 API สำหรับหน้า Dashboard ผู้ดูแลระบบ 🌟
// ==========================================

const ROOM_CODE_MAX_LENGTH = 255;
const FLOOR_MAX_LENGTH = 50;

// ตรวจสอบว่าข้อมูลห้องที่ส่งมาครบและถูกต้องหรือไม่ คืนข้อความ error ถ้าไม่ผ่าน หรือ null ถ้าผ่าน
function validateRoomInput({ room_code, building_name, floor }) {
    if (typeof room_code !== 'string' || room_code.trim() === '') {
        return 'กรุณากรอกรหัส/ชื่อห้อง';
    }
    if (room_code.trim().length > ROOM_CODE_MAX_LENGTH) {
        return `รหัส/ชื่อห้องต้องไม่เกิน ${ROOM_CODE_MAX_LENGTH} ตัวอักษร`;
    }
    if (typeof building_name !== 'string' || building_name.trim() === '') {
        return 'กรุณาระบุอาคาร';
    }
    if (typeof floor !== 'string' || floor.trim() === '') {
        return 'กรุณาระบุชั้น';
    }
    if (floor.trim().length > FLOOR_MAX_LENGTH) {
        return `ข้อมูลชั้นต้องไม่เกิน ${FLOOR_MAX_LENGTH} ตัวอักษร`;
    }
    return null;
}

// ตรวจสอบว่ามีห้องรหัสเดียวกันในอาคารเดียวกันอยู่แล้วหรือไม่ (excludeId ใช้ตอนแก้ไขเพื่อไม่ชนกับตัวเอง)
function findDuplicateRoom(roomCode, buildingName, excludeId, callback) {
    let sql = 'SELECT id FROM rooms WHERE room_code = ? AND building_name = ?';
    const params = [roomCode, buildingName];

    if (excludeId !== null) {
        sql += ' AND id != ?';
        params.push(excludeId);
    }

    db.query(sql, params, (err, results) => {
        if (err) return callback(err);
        callback(null, results.length > 0);
    });
}

// 1. API เพิ่มห้องเรียนใหม่ (Create - รองรับ floor)
app.post('/api/rooms', requireAdmin, (req, res) => {
    const { room_code, building_name, floor, pin_x, pin_y } = req.body || {};

    const validationError = validateRoomInput({ room_code, building_name, floor });
    if (validationError) {
        return res.status(400).json({ error: validationError });
    }

    const trimmedCode = room_code.trim();
    const trimmedBuilding = building_name.trim();
    const trimmedFloor = floor.trim();

    findDuplicateRoom(trimmedCode, trimmedBuilding, null, (err, isDuplicate) => {
        if (err) return res.status(500).json({ error: err.message });
        if (isDuplicate) {
            return res.status(409).json({ error: 'มีห้องนี้ในอาคารเดียวกันอยู่แล้ว' });
        }

        const sql = "INSERT INTO rooms (room_code, building_name, floor, pin_x, pin_y) VALUES (?, ?, ?, ?, ?)";
        db.query(sql, [trimmedCode, trimmedBuilding, trimmedFloor, pin_x ?? 0, pin_y ?? 0], (err, results) => {
            if (err) return res.status(500).json({ error: err.message });
            res.json({ message: "เพิ่มข้อมูลสำเร็จ!", id: results.insertId });
        });
    });
});

// 2. API แก้ไขข้อมูล/อัปเดตพิกัดแผนที่ (Update - รองรับ floor)
app.put('/api/rooms/:id', requireAdmin, (req, res) => {
    const roomId = req.params.id;
    const { room_code, building_name, floor, pin_x, pin_y } = req.body || {};

    const validationError = validateRoomInput({ room_code, building_name, floor });
    if (validationError) {
        return res.status(400).json({ error: validationError });
    }

    const trimmedCode = room_code.trim();
    const trimmedBuilding = building_name.trim();
    const trimmedFloor = floor.trim();

    findDuplicateRoom(trimmedCode, trimmedBuilding, roomId, (err, isDuplicate) => {
        if (err) return res.status(500).json({ error: err.message });
        if (isDuplicate) {
            return res.status(409).json({ error: 'มีห้องนี้ในอาคารเดียวกันอยู่แล้ว' });
        }

        const sql = "UPDATE rooms SET room_code=?, building_name=?, floor=?, pin_x=?, pin_y=? WHERE id=?";
        db.query(sql, [trimmedCode, trimmedBuilding, trimmedFloor, pin_x ?? 0, pin_y ?? 0, roomId], (err, results) => {
            if (err) return res.status(500).json({ error: err.message });
            res.json({ message: "อัปเดตข้อมูลสำเร็จ!" });
        });
    });
});

// 3. API ลบห้องเรียน (Delete)
app.delete('/api/rooms/:id', requireAdmin, (req, res) => {
    const roomId = req.params.id;
    const sql = "DELETE FROM rooms WHERE id=?";
    
    db.query(sql, [roomId], (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: "ลบข้อมูลสำเร็จ!" });
    });
});

// 4. สั่งให้เซิร์ฟเวอร์เปิดทำงาน
app.listen(port, () => {
    console.log(`🚀 Server เปิดทำงานแล้วที่ http://localhost:${port}`);
});
