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
    const isAdmin = Boolean(req.session && req.session.isAdmin);
    res.json({ isAdmin, username: isAdmin ? ADMIN_USERNAME : null });
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

// 🌟 rooms ตอนนี้ผูกกับ buildings ผ่าน building_id (FK) แทนการเก็บชื่อตึกซ้ำในทุกแถว
// query กลางนี้ join กลับมาเป็น building_name ให้ shape ของ JSON เหมือนเดิมทุกจุดที่แอป Flutter เรียกใช้อยู่
const ROOM_SELECT_BASE = `
    SELECT rooms.id, rooms.room_code, buildings.name AS building_name, rooms.floor,
           rooms.pin_x, rooms.pin_y, rooms.room_type, rooms.capacity, rooms.status, rooms.amenities,
           rooms.building_id
    FROM rooms
    JOIN buildings ON buildings.id = rooms.building_id
`;

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

    const sql = `${ROOM_SELECT_BASE} WHERE rooms.room_code LIKE ? ORDER BY buildings.name, rooms.floor, rooms.room_code LIMIT 20`;

    db.query(sql, [`%${query}%`], (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        res.json(results);
    });
});

app.get('/api/search/:room', (req, res) => {
    const roomCode = req.params.room;
    const sql = `${ROOM_SELECT_BASE} WHERE rooms.room_code = ?`;

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
    const sql = `${ROOM_SELECT_BASE} WHERE buildings.name = ?`;

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

// 🌟 แปลนอาคาร: บอกว่าตึก+ชั้นไหน ใช้ไฟล์รูปแปลนอะไร ขนาดเท่าไหร่ (ตำแหน่งหมุดเป็น % ของขนาดรูปนี้) 🌟
// ระบุ width/height ของไฟล์จริงไว้ตรงนี้ เพื่อให้แอปคำนวณสัดส่วนรูปได้ทันทีโดยไม่ต้องรอโหลดรูปมาวัดขนาดเอง (กันภาพยืด)
const FLOOR_PLANS = {
    'อาคารเรียนรวม 3 (ศร.3)': {
        '1': { image: '/floorplans/lh3-floor-1.png', width: 1506, height: 1045 },
        '2': { image: '/floorplans/lh3-floor-2.png', width: 1516, height: 1037 },
        '3': { image: '/floorplans/lh3-floor-3.png', width: 1498, height: 1050 },
    },
};

app.get('/api/floorplan', (req, res) => {
    const building = typeof req.query.building === 'string' ? req.query.building : '';
    const floor = typeof req.query.floor === 'string' ? req.query.floor : '';

    const plan = FLOOR_PLANS[building]?.[floor];
    if (!plan) {
        return res.status(404).json({ error: 'ยังไม่มีแผนที่สำหรับอาคาร/ชั้นนี้' });
    }
    res.json(plan);
});

const ROOM_TYPE_MAX_LENGTH = 50;
const ROOM_STATUSES = ['active', 'maintenance'];

// ตรวจสอบว่าข้อมูลห้องที่ส่งมาครบและถูกต้องหรือไม่ คืนข้อความ error ถ้าไม่ผ่าน หรือ null ถ้าผ่าน
function validateRoomInput({ room_code, building_name, floor, pin_x, pin_y, room_type, capacity, status, amenities }) {
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
    for (const [label, value] of [['pin_x', pin_x], ['pin_y', pin_y]]) {
        if (value === null || value === undefined) continue;
        const num = Number(value);
        if (!Number.isFinite(num) || num < 0 || num > 100) {
            return `ค่าพิกัด ${label} ต้องเป็นตัวเลข 0-100`;
        }
    }
    if (room_type !== null && room_type !== undefined && room_type !== '') {
        if (typeof room_type !== 'string' || room_type.length > ROOM_TYPE_MAX_LENGTH) {
            return `ประเภทห้องต้องไม่เกิน ${ROOM_TYPE_MAX_LENGTH} ตัวอักษร`;
        }
    }
    if (capacity !== null && capacity !== undefined && capacity !== '') {
        const num = Number(capacity);
        if (!Number.isInteger(num) || num < 0) {
            return 'ความจุห้องต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป';
        }
    }
    if (status !== null && status !== undefined && status !== '' && !ROOM_STATUSES.includes(status)) {
        return 'สถานะห้องไม่ถูกต้อง';
    }
    if (amenities !== null && amenities !== undefined && typeof amenities !== 'object') {
        return 'ข้อมูลสิ่งอำนวยความสะดวกไม่ถูกต้อง';
    }
    return null;
}

// หา building_id จากชื่ออาคาร คืน null ถ้าไม่พบ
function findBuildingIdByName(buildingName, callback) {
    db.query('SELECT id FROM buildings WHERE name = ?', [buildingName], (err, results) => {
        if (err) return callback(err);
        callback(null, results.length > 0 ? results[0].id : null);
    });
}

// ตรวจสอบว่ามีห้องรหัสเดียวกันในอาคารเดียวกันอยู่แล้วหรือไม่ (excludeId ใช้ตอนแก้ไขเพื่อไม่ชนกับตัวเอง)
function findDuplicateRoom(roomCode, buildingId, excludeId, callback) {
    let sql = 'SELECT id FROM rooms WHERE room_code = ? AND building_id = ?';
    const params = [roomCode, buildingId];

    if (excludeId !== null) {
        sql += ' AND id != ?';
        params.push(excludeId);
    }

    db.query(sql, params, (err, results) => {
        if (err) return callback(err);
        callback(null, results.length > 0);
    });
}

// 1. API เพิ่มห้องเรียนใหม่ (Create - รองรับ floor + ฟิลด์ใหม่)
app.post('/api/rooms', requireAdmin, (req, res) => {
    const { room_code, building_name, floor, pin_x, pin_y, room_type, capacity, status, amenities } = req.body || {};

    const validationError = validateRoomInput({ room_code, building_name, floor, pin_x, pin_y, room_type, capacity, status, amenities });
    if (validationError) {
        return res.status(400).json({ error: validationError });
    }

    const trimmedCode = room_code.trim();
    const trimmedBuilding = building_name.trim();
    const trimmedFloor = floor.trim();

    findBuildingIdByName(trimmedBuilding, (err, buildingId) => {
        if (err) return res.status(500).json({ error: err.message });
        if (buildingId === null) {
            return res.status(400).json({ error: 'ไม่พบอาคารนี้ในระบบ กรุณาเพิ่มอาคารก่อน' });
        }

        findDuplicateRoom(trimmedCode, buildingId, null, (err, isDuplicate) => {
            if (err) return res.status(500).json({ error: err.message });
            if (isDuplicate) {
                return res.status(409).json({ error: 'มีห้องนี้ในอาคารเดียวกันอยู่แล้ว' });
            }

            const sql = `
                INSERT INTO rooms (room_code, building_id, floor, pin_x, pin_y, room_type, capacity, status, amenities)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            `;
            const params = [
                trimmedCode, buildingId, trimmedFloor, pin_x ?? null, pin_y ?? null,
                room_type || null, capacity ?? null, status || 'active',
                amenities ? JSON.stringify(amenities) : null,
            ];
            db.query(sql, params, (err, results) => {
                if (err) return res.status(500).json({ error: err.message });
                res.json({ message: "เพิ่มข้อมูลสำเร็จ!", id: results.insertId });
            });
        });
    });
});

// 2. API แก้ไขข้อมูล/อัปเดตพิกัดแผนที่ (Update - รองรับ floor + ฟิลด์ใหม่)
app.put('/api/rooms/:id', requireAdmin, (req, res) => {
    const roomId = req.params.id;
    const { room_code, building_name, floor, pin_x, pin_y, room_type, capacity, status, amenities } = req.body || {};

    const validationError = validateRoomInput({ room_code, building_name, floor, pin_x, pin_y, room_type, capacity, status, amenities });
    if (validationError) {
        return res.status(400).json({ error: validationError });
    }

    const trimmedCode = room_code.trim();
    const trimmedBuilding = building_name.trim();
    const trimmedFloor = floor.trim();

    findBuildingIdByName(trimmedBuilding, (err, buildingId) => {
        if (err) return res.status(500).json({ error: err.message });
        if (buildingId === null) {
            return res.status(400).json({ error: 'ไม่พบอาคารนี้ในระบบ กรุณาเพิ่มอาคารก่อน' });
        }

        findDuplicateRoom(trimmedCode, buildingId, roomId, (err, isDuplicate) => {
            if (err) return res.status(500).json({ error: err.message });
            if (isDuplicate) {
                return res.status(409).json({ error: 'มีห้องนี้ในอาคารเดียวกันอยู่แล้ว' });
            }

            const sql = `
                UPDATE rooms
                SET room_code=?, building_id=?, floor=?, pin_x=?, pin_y=?, room_type=?, capacity=?, status=?, amenities=?
                WHERE id=?
            `;
            const params = [
                trimmedCode, buildingId, trimmedFloor, pin_x ?? null, pin_y ?? null,
                room_type || null, capacity ?? null, status || 'active',
                amenities ? JSON.stringify(amenities) : null, roomId,
            ];
            db.query(sql, params, (err, results) => {
                if (err) return res.status(500).json({ error: err.message });
                res.json({ message: "อัปเดตข้อมูลสำเร็จ!" });
            });
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

// ==========================================
// 🌟 API จัดการอาคาร (Buildings) 🌟
// ==========================================

const BUILDING_CODE_MAX_LENGTH = 20;
const BUILDING_NAME_MAX_LENGTH = 255;

function validateBuildingInput({ code, name }) {
    if (typeof code !== 'string' || code.trim() === '') {
        return 'กรุณากรอกรหัสอาคาร';
    }
    if (code.trim().length > BUILDING_CODE_MAX_LENGTH) {
        return `รหัสอาคารต้องไม่เกิน ${BUILDING_CODE_MAX_LENGTH} ตัวอักษร`;
    }
    if (typeof name !== 'string' || name.trim() === '') {
        return 'กรุณากรอกชื่ออาคาร';
    }
    if (name.trim().length > BUILDING_NAME_MAX_LENGTH) {
        return `ชื่ออาคารต้องไม่เกิน ${BUILDING_NAME_MAX_LENGTH} ตัวอักษร`;
    }
    return null;
}

// รายชื่ออาคารทั้งหมด พร้อมสถิติจำนวนชั้น/จำนวนห้อง คำนวณสดจากตาราง rooms
app.get('/api/buildings', (req, res) => {
    const sql = `
        SELECT buildings.id, buildings.code, buildings.name, buildings.description, buildings.location,
               COUNT(rooms.id) AS room_count,
               COUNT(DISTINCT rooms.floor) AS floor_count
        FROM buildings
        LEFT JOIN rooms ON rooms.building_id = buildings.id
        GROUP BY buildings.id
        ORDER BY buildings.name
    `;
    db.query(sql, (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(results);
    });
});

app.post('/api/buildings', requireAdmin, (req, res) => {
    const { code, name, description, location } = req.body || {};
    const validationError = validateBuildingInput({ code, name });
    if (validationError) {
        return res.status(400).json({ error: validationError });
    }

    const sql = 'INSERT INTO buildings (code, name, description, location) VALUES (?, ?, ?, ?)';
    db.query(sql, [code.trim(), name.trim(), description || null, location || null], (err, results) => {
        if (err) {
            if (err.code === 'ER_DUP_ENTRY') {
                return res.status(409).json({ error: 'มีรหัสหรือชื่ออาคารนี้อยู่แล้ว' });
            }
            return res.status(500).json({ error: err.message });
        }
        res.json({ message: 'เพิ่มอาคารสำเร็จ!', id: results.insertId });
    });
});

app.put('/api/buildings/:id', requireAdmin, (req, res) => {
    const buildingId = req.params.id;
    const { code, name, description, location } = req.body || {};
    const validationError = validateBuildingInput({ code, name });
    if (validationError) {
        return res.status(400).json({ error: validationError });
    }

    const sql = 'UPDATE buildings SET code=?, name=?, description=?, location=? WHERE id=?';
    db.query(sql, [code.trim(), name.trim(), description || null, location || null, buildingId], (err) => {
        if (err) {
            if (err.code === 'ER_DUP_ENTRY') {
                return res.status(409).json({ error: 'มีรหัสหรือชื่ออาคารนี้อยู่แล้ว' });
            }
            return res.status(500).json({ error: err.message });
        }
        res.json({ message: 'อัปเดตอาคารสำเร็จ!' });
    });
});

app.delete('/api/buildings/:id', requireAdmin, (req, res) => {
    const buildingId = req.params.id;
    db.query('DELETE FROM buildings WHERE id=?', [buildingId], (err) => {
        if (err) {
            if (err.code === 'ER_ROW_IS_REFERENCED_2' || err.code === 'ER_ROW_IS_REFERENCED') {
                return res.status(409).json({ error: 'ลบไม่ได้ เพราะยังมีห้องเรียนอยู่ในอาคารนี้' });
            }
            return res.status(500).json({ error: err.message });
        }
        res.json({ message: 'ลบอาคารสำเร็จ!' });
    });
});

// สรุปสถิติภาพรวมสำหรับหน้า Overview ของ Admin Dashboard
app.get('/api/admin/overview', requireAdmin, (req, res) => {
    const sql = `
        SELECT
            (SELECT COUNT(*) FROM buildings) AS building_count,
            (SELECT COUNT(*) FROM rooms) AS room_count,
            (SELECT COUNT(*) FROM rooms WHERE status = 'active') AS active_room_count,
            (SELECT COUNT(*) FROM rooms WHERE status = 'maintenance') AS maintenance_room_count
    `;
    db.query(sql, (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        const stats = results[0];
        res.json({
            building_count: stats.building_count,
            room_count: stats.room_count,
            active_room_count: stats.active_room_count,
            maintenance_room_count: stats.maintenance_room_count,
            // ยังไม่มีระบบภาพ 360°/สถิติการเข้าชม (มาในไมล์สโตนถัดไป) — คืนค่า 0 ไปก่อน
            rooms_with_panorama_count: 0,
            visits_today: 0,
        });
    });
});

// 4. สั่งให้เซิร์ฟเวอร์เปิดทำงาน
app.listen(port, () => {
    console.log(`🚀 Server เปิดทำงานแล้วที่ http://localhost:${port}`);
});
