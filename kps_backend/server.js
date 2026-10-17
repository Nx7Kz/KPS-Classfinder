const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const session = require('express-session');
const bcrypt = require('bcryptjs');
const rateLimit = require('express-rate-limit');
const multer = require('multer');
const { parse: parseCsv } = require('csv-parse/sync');
const { imageSize } = require('image-size');
const sharp = require('sharp');

const app = express();
const port = 3000;

app.set('trust proxy', 1);
app.use(cors({ origin: true, credentials: true }));
// นำเข้า CSV ต้องรับ body ใหญ่กว่าปกติ จึงประกาศ parser ของ route นี้ก่อน parser ตัวหลัก
app.use('/api/admin/rooms/import', express.json({ limit: '3mb' }));
app.use(express.json());

// ==========================================
// 🌟 ฐานข้อมูล 🌟
// ==========================================

// ใช้ pool แทน connection เดี่ยว เพราะ MySQL container อาจพร้อมช้ากว่า backend ตอน docker compose up ครั้งแรก
// pool จะขอ connection ใหม่ต่อ query แทนที่จะค้างสถานะ error ไว้ถาวร
const db = mysql.createPool({
    host: 'db',
    user: 'root',
    password: '',
    database: 'kps_classfinder',
    waitForConnections: true,
    connectionLimit: 10,
});
const pdb = db.promise();

class HttpError extends Error {
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}

// ห่อ handler แบบ async ให้ error ถูกส่งกลับเป็น JSON เสมอ
function asyncRoute(handler) {
    return (req, res, next) => {
        Promise.resolve(handler(req, res, next)).catch((err) => {
            if (err instanceof HttpError) {
                return res.status(err.status).json({ error: err.message });
            }
            console.error(err);
            res.status(500).json({ error: 'เกิดข้อผิดพลาดภายในระบบ กรุณาลองใหม่อีกครั้ง' });
        });
    };
}

// ==========================================
// 🌟 ระบบเข้าสู่ระบบสำหรับ Admin Dashboard 🌟
// ==========================================
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD_HASH
    || bcrypt.hashSync(process.env.ADMIN_PASSWORD || 'admin1234', 10);
const PASSWORD_MIN_LENGTH = 8;
const PASSWORD_MAX_BYTES = 72; // bcrypt ใช้เพียง 72 ไบต์แรกของรหัสผ่าน

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

// รหัสผ่านที่เปลี่ยนผ่านหน้า Settings เก็บในฐานข้อมูล ถ้ายังไม่เคยเปลี่ยนให้ใช้ค่าจาก environment
async function getAdminPasswordHash() {
    try {
        const [rows] = await pdb.query("SELECT setting_value FROM admin_settings WHERE setting_key = 'admin_password_hash'");
        return rows.length > 0 ? rows[0].setting_value : ADMIN_PASSWORD_HASH;
    } catch (err) {
        // ฐานข้อมูลเก่าที่ยังไม่มีตาราง (ensureDashboardSchema กำลังสร้างอยู่) ยังต้องล็อกอินได้ด้วยรหัสจาก environment
        if (err.code === 'ER_NO_SUCH_TABLE') return ADMIN_PASSWORD_HASH;
        throw err;
    }
}

// ==========================================
// 🌟 บันทึกกิจกรรม (System Logs) 🌟
// ==========================================
// fire-and-forget: ถ้าบันทึกไม่สำเร็จ จะไม่ทำให้คำสั่งหลักล้มเหลว และห้ามใส่รหัสผ่าน/ข้อมูลลับใน detail
function logActivity(req, { action, entity, entityId = null, detail = null, username = null }) {
    const actor = username || (req.session && req.session.isAdmin ? ADMIN_USERNAME : null);
    const sql = 'INSERT INTO activity_logs (action, entity, entity_id, detail, username, ip) VALUES (?, ?, ?, ?, ?, ?)';
    const params = [
        action, entity, entityId,
        detail === null ? null : String(detail).slice(0, 500),
        actor === null ? null : String(actor).slice(0, 100),
        String(req.ip || '').replace(/^::ffff:/, '').slice(0, 64),
    ];
    db.query(sql, params, (err) => {
        if (err) console.error('บันทึก activity log ไม่สำเร็จ:', err.message);
    });
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

const changePasswordLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 5,
    standardHeaders: true,
    legacyHeaders: false,
    skipSuccessfulRequests: true,
    message: { error: 'ใส่รหัสผ่านปัจจุบันผิดหลายครั้งเกินไป กรุณาลองใหม่อีกครั้งในอีก 15 นาที' },
});

app.post('/api/login', loginLimiter, asyncRoute(async (req, res) => {
    const { username, password } = req.body || {};

    const rejectLogin = () => {
        logActivity(req, {
            action: 'login_failed', entity: 'session', detail: 'ล็อกอินไม่สำเร็จ',
            username: typeof username === 'string' ? username : null,
        });
        return res.status(401).json({ error: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });
    };

    if (typeof username !== 'string' || typeof password !== 'string' || username !== ADMIN_USERNAME) {
        return rejectLogin();
    }
    const passwordHash = await getAdminPasswordHash();
    if (!bcrypt.compareSync(password, passwordHash)) {
        return rejectLogin();
    }

    req.session.isAdmin = true;
    logActivity(req, { action: 'login', entity: 'session', detail: 'เข้าสู่ระบบสำเร็จ', username });
    res.json({ message: 'เข้าสู่ระบบสำเร็จ' });
}));

app.post('/api/logout', (req, res) => {
    if (req.session && req.session.isAdmin) {
        logActivity(req, { action: 'logout', entity: 'session', detail: 'ออกจากระบบ' });
    }
    req.session.destroy(() => {
        res.json({ message: 'ออกจากระบบแล้ว' });
    });
});

app.get('/api/session', (req, res) => {
    const isAdmin = Boolean(req.session && req.session.isAdmin);
    res.json({ isAdmin, username: isAdmin ? ADMIN_USERNAME : null });
});

app.post('/api/admin/change-password', requireAdmin, changePasswordLimiter, asyncRoute(async (req, res) => {
    const { current_password: currentPassword, new_password: newPassword } = req.body || {};

    if (typeof currentPassword !== 'string' || typeof newPassword !== 'string' || currentPassword === '') {
        throw new HttpError(400, 'กรุณากรอกรหัสผ่านปัจจุบันและรหัสผ่านใหม่');
    }
    if (newPassword.length < PASSWORD_MIN_LENGTH) {
        throw new HttpError(400, `รหัสผ่านใหม่ต้องยาวอย่างน้อย ${PASSWORD_MIN_LENGTH} ตัวอักษร`);
    }
    if (Buffer.byteLength(newPassword, 'utf8') > PASSWORD_MAX_BYTES) {
        throw new HttpError(400, `รหัสผ่านใหม่ยาวเกินไป (ไม่เกิน ${PASSWORD_MAX_BYTES} ไบต์)`);
    }
    if (newPassword === currentPassword) {
        throw new HttpError(400, 'รหัสผ่านใหม่ต้องไม่เหมือนรหัสผ่านปัจจุบัน');
    }

    const currentHash = await getAdminPasswordHash();
    if (!bcrypt.compareSync(currentPassword, currentHash)) {
        throw new HttpError(400, 'รหัสผ่านปัจจุบันไม่ถูกต้อง');
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    await pdb.query(
        `INSERT INTO admin_settings (setting_key, setting_value) VALUES ('admin_password_hash', ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`,
        [newHash]
    );
    logActivity(req, { action: 'change_password', entity: 'admin', detail: 'เปลี่ยนรหัสผ่านผู้ดูแลระบบ' });
    res.json({ message: 'เปลี่ยนรหัสผ่านสำเร็จ!' });
}));

// ==========================================
// 🌟 ไฟล์ที่อัปโหลด (แผนผังชั้น / ภาพพาโนรามา) 🌟
// ==========================================
const PUBLIC_DIR = path.join(__dirname, 'public');
const FLOORPLAN_DIR = path.join(PUBLIC_DIR, 'floorplans');
const PANORAMA_DIR = path.join(PUBLIC_DIR, 'panoramas');
const COVER_DIR = path.join(PUBLIC_DIR, 'covers');
const TOUR_IMAGE_DIR = path.join(PUBLIC_DIR, 'tour-images');
fs.mkdirSync(FLOORPLAN_DIR, { recursive: true });
fs.mkdirSync(PANORAMA_DIR, { recursive: true });
fs.mkdirSync(COVER_DIR, { recursive: true });
fs.mkdirSync(TOUR_IMAGE_DIR, { recursive: true });

// 🌟 สั่งให้ Express เปิดใช้งานไฟล์เว็บจากโฟลเดอร์ public 🌟
app.use(express.static(PUBLIC_DIR));

// ไลบรารีของหน้าเดินชม (Photo Sphere Viewer + three.js) เสิร์ฟจาก node_modules ไม่ต้องพึ่ง CDN
const NODE_MODULES_DIR = path.join(__dirname, 'node_modules');
app.use('/vendor/three', express.static(path.join(NODE_MODULES_DIR, 'three', 'build')));
for (const name of ['core', 'virtual-tour-plugin', 'map-plugin', 'markers-plugin']) {
    app.use(`/vendor/psv/${name}`, express.static(path.join(NODE_MODULES_DIR, '@photo-sphere-viewer', name)));
}

const IMAGE_MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
const IMAGE_EXT_BY_TYPE = { png: '.png', jpg: '.jpg', webp: '.webp' }; // ไม่รับ SVG เพื่อกัน XSS
const IMAGE_TYPE_ERROR = 'ไฟล์ต้องเป็นรูป PNG, JPG หรือ WebP เท่านั้น';

// ไฟล์ที่ระบบสร้างเองขึ้นต้นด้วย prefix เหล่านี้ ไฟล์ตั้งต้น (เช่น lh3-floor-1.png) จะไม่ถูกลบ
const UPLOAD_RULES = [
    { urlPrefix: '/floorplans/', filePrefix: 'floorplan_', dir: FLOORPLAN_DIR },
    { urlPrefix: '/panoramas/', filePrefix: 'pano_', dir: PANORAMA_DIR },
    { urlPrefix: '/covers/', filePrefix: 'cover_', dir: COVER_DIR },
    { urlPrefix: '/tour-images/', filePrefix: 'tour_', dir: TOUR_IMAGE_DIR },
];

function createImageUploader(maxBytes) {
    return multer({
        storage: multer.memoryStorage(),
        limits: { fileSize: maxBytes, files: 1 },
        fileFilter: (req, file, cb) => {
            if (!IMAGE_MIME_TYPES.includes(file.mimetype)) return cb(new Error(IMAGE_TYPE_ERROR));
            cb(null, true);
        },
    });
}

const floorPlanUploader = createImageUploader(10 * 1024 * 1024);
const panoramaUploader = createImageUploader(20 * 1024 * 1024);
const coverUploader = createImageUploader(10 * 1024 * 1024);
const tourImageUploader = createImageUploader(40 * 1024 * 1024); // ภาพจากกล้อง 360° ต้นฉบับ (เช่น 8000×4000) ใหญ่ ระบบย่อให้เอง

function handleUpload(uploader, fieldName, maxMb) {
    return (req, res, next) => {
        uploader.single(fieldName)(req, res, (err) => {
            if (!err) return next();
            if (err.code === 'LIMIT_FILE_SIZE') {
                return res.status(413).json({ error: `ไฟล์ใหญ่เกินไป (สูงสุด ${maxMb} MB)` });
            }
            if (err.code === 'LIMIT_UNEXPECTED_FILE') {
                return res.status(400).json({ error: 'ฟิลด์ไฟล์ไม่ถูกต้อง' });
            }
            return res.status(400).json({ error: err.message || 'อัปโหลดไฟล์ไม่สำเร็จ' });
        });
    };
}

// ตรวจว่าเป็นรูปจริงจากเนื้อไฟล์ (ไม่เชื่อ mimetype ที่ client ส่งมา) แล้วบันทึกด้วยชื่อที่ระบบสุ่มเอง
async function saveUploadedImage(file, rule) {
    let info;
    try {
        info = imageSize(file.buffer);
    } catch (err) {
        throw new HttpError(400, 'ไฟล์รูปไม่ถูกต้องหรือเสียหาย');
    }
    const ext = IMAGE_EXT_BY_TYPE[info.type];
    if (!ext || !info.width || !info.height) {
        throw new HttpError(400, IMAGE_TYPE_ERROR);
    }
    const fileName = `${rule.filePrefix}${crypto.randomBytes(8).toString('hex')}${ext}`;
    await fs.promises.writeFile(path.join(rule.dir, fileName), file.buffer);
    return { url: `${rule.urlPrefix}${fileName}`, width: info.width, height: info.height };
}

function removeUploadedFiles(urls) {
    for (const url of urls) {
        if (typeof url !== 'string') continue;
        const rule = UPLOAD_RULES.find(item => url.startsWith(item.urlPrefix));
        if (!rule) continue;
        const fileName = path.basename(url.slice(rule.urlPrefix.length));
        if (!fileName.startsWith(rule.filePrefix)) continue;
        fs.unlink(path.join(rule.dir, fileName), () => {});
    }
}

const FLOORPLAN_RULE = UPLOAD_RULES[0];
const PANORAMA_RULE = UPLOAD_RULES[1];
const COVER_RULE = UPLOAD_RULES[2];
const TOUR_IMAGE_RULE = UPLOAD_RULES[3];

// ==========================================
// 🌟 API สำหรับแอป (อ่านอย่างเดียว) 🌟
// ==========================================

// 🌟 rooms ตอนนี้ผูกกับ buildings ผ่าน building_id (FK) แทนการเก็บชื่อตึกซ้ำในทุกแถว
// query กลางนี้ join กลับมาเป็น building_name ให้ shape ของ JSON เหมือนเดิมทุกจุดที่แอป Flutter เรียกใช้อยู่
const ROOM_SELECT_BASE = `
    SELECT rooms.id, rooms.room_code, buildings.name AS building_name, rooms.floor,
           rooms.pin_x, rooms.pin_y, rooms.room_type, rooms.capacity, rooms.status, rooms.amenities,
           rooms.building_id,
           (SELECT COUNT(*) FROM panoramas WHERE panoramas.room_id = rooms.id) AS panorama_count,
           (SELECT tp.id FROM tour_points tp WHERE tp.room_id = rooms.id AND tp.x IS NOT NULL
               ORDER BY tp.id LIMIT 1) AS tour_point_id
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
// ค้นได้ทั้งรหัสห้อง ชื่อ/รหัสอาคาร และประเภทห้อง โดยเรียงผลที่ตรงที่สุดขึ้นก่อน:
// รหัสห้องตรงเป๊ะ > รหัสห้องขึ้นต้นด้วยคำค้น > รหัสห้องมีคำค้น > ตรงชื่อ/รหัสอาคาร > ตรงประเภทห้อง
app.get('/api/rooms/search', (req, res) => {
    const query = typeof req.query.q === 'string' ? req.query.q.trim().slice(0, 100) : '';

    if (!query) {
        return res.json([]);
    }

    // escape อักขระพิเศษของ LIKE เพื่อให้ "_" หรือ "%" ที่ผู้ใช้พิมพ์ถูกค้นตามตัวอักษรจริง
    const escaped = query.replace(/[\\%_]/g, char => `\\${char}`);
    const contains = `%${escaped}%`;
    const prefix = `${escaped}%`;

    const sql = `${ROOM_SELECT_BASE}
        WHERE rooms.room_code LIKE ? OR buildings.name LIKE ? OR buildings.code LIKE ? OR rooms.room_type LIKE ?
        ORDER BY
            CASE
                WHEN rooms.room_code = ? THEN 0
                WHEN rooms.room_code LIKE ? THEN 1
                WHEN rooms.room_code LIKE ? THEN 2
                WHEN buildings.name LIKE ? OR buildings.code LIKE ? THEN 3
                ELSE 4
            END,
            buildings.name, rooms.floor, rooms.room_code
        LIMIT 50`;
    const params = [contains, contains, contains, contains, query, prefix, contains, contains, contains];

    db.query(sql, params, (err, results) => {
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

// 🌟 แปลนอาคาร: บอกว่าตึก+ชั้นไหน ใช้ไฟล์รูปแปลนอะไร ขนาดเท่าไหร่ (ตำแหน่งหมุดเป็น % ของขนาดรูปนี้) 🌟
// ข้อมูลมาจากตาราง floor_plans (จัดการผ่านเมนู Floor Plans) โดย shape ของ JSON ยังเหมือนเดิมสำหรับแอป Flutter
app.get('/api/floorplan', (req, res) => {
    const building = typeof req.query.building === 'string' ? req.query.building : '';
    const floor = typeof req.query.floor === 'string' ? req.query.floor : '';

    const sql = `
        SELECT floor_plans.image_url AS image, floor_plans.width, floor_plans.height
        FROM floor_plans
        JOIN buildings ON buildings.id = floor_plans.building_id
        WHERE buildings.name = ? AND floor_plans.floor = ?
    `;
    db.query(sql, [building, floor], (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length === 0) {
            return res.status(404).json({ error: 'ยังไม่มีแผนที่สำหรับอาคาร/ชั้นนี้' });
        }
        res.json(results[0]);
    });
});

// ==========================================
// 🌟 API จัดการห้องเรียน (Rooms) 🌟
// ==========================================

const ROOM_CODE_MAX_LENGTH = 255;
const FLOOR_MAX_LENGTH = 50;
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
                logActivity(req, {
                    action: 'create', entity: 'room', entityId: results.insertId,
                    detail: `เพิ่มห้อง "${trimmedCode}" (${trimmedBuilding} ชั้น ${trimmedFloor})`,
                });
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
                logActivity(req, {
                    action: 'update', entity: 'room', entityId: Number(roomId) || null,
                    detail: `แก้ไขห้อง "${trimmedCode}" (${trimmedBuilding} ชั้น ${trimmedFloor})`,
                });
                res.json({ message: "อัปเดตข้อมูลสำเร็จ!" });
            });
        });
    });
});

// 3. API ลบห้องเรียน (Delete) — ลบไฟล์ภาพพาโนรามาของห้องนี้ออกจากดิสก์ด้วย
app.delete('/api/rooms/:id', requireAdmin, asyncRoute(async (req, res) => {
    const roomId = req.params.id;
    const [rooms] = await pdb.query('SELECT room_code FROM rooms WHERE id = ?', [roomId]);
    const [panoramas] = await pdb.query('SELECT image_url FROM panoramas WHERE room_id = ?', [roomId]);

    await pdb.query('DELETE FROM rooms WHERE id = ?', [roomId]);
    removeUploadedFiles(panoramas.map(item => item.image_url));

    logActivity(req, {
        action: 'delete', entity: 'room', entityId: Number(roomId) || null,
        detail: `ลบห้อง "${rooms.length > 0 ? rooms[0].room_code : roomId}"`,
    });
    res.json({ message: "ลบข้อมูลสำเร็จ!" });
}));

// 3.1 API ลบห้องเรียนหลายห้องพร้อมกัน (Bulk Delete) รับ { ids: [1, 2, 3] }
const BULK_DELETE_MAX = 500;

app.post('/api/rooms/bulk-delete', requireAdmin, asyncRoute(async (req, res) => {
    const { ids } = req.body || {};

    if (!Array.isArray(ids) || ids.length === 0) {
        throw new HttpError(400, 'กรุณาเลือกห้องที่ต้องการลบ');
    }
    if (ids.length > BULK_DELETE_MAX) {
        throw new HttpError(400, `ลบได้ครั้งละไม่เกิน ${BULK_DELETE_MAX} ห้อง`);
    }

    const roomIds = ids.map(Number);
    if (roomIds.some(id => !Number.isInteger(id) || id <= 0)) {
        throw new HttpError(400, 'รูปแบบรหัสห้องไม่ถูกต้อง');
    }

    const [rooms] = await pdb.query('SELECT room_code FROM rooms WHERE id IN (?)', [roomIds]);
    const [panoramas] = await pdb.query('SELECT image_url FROM panoramas WHERE room_id IN (?)', [roomIds]);
    const [result] = await pdb.query('DELETE FROM rooms WHERE id IN (?)', [roomIds]);
    removeUploadedFiles(panoramas.map(item => item.image_url));

    const names = rooms.slice(0, 10).map(room => room.room_code).join(', ');
    logActivity(req, {
        action: 'delete', entity: 'room',
        detail: `ลบห้อง ${result.affectedRows} ห้อง: ${names}${rooms.length > 10 ? ' ...' : ''}`,
    });
    res.json({ message: `ลบห้องเรียน ${result.affectedRows} ห้องสำเร็จ!`, deleted: result.affectedRows });
}));

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
               buildings.cover_image,
               COUNT(rooms.id) AS room_count,
               COUNT(DISTINCT rooms.floor) AS floor_count,
               -- ภาพสำรองเมื่อยังไม่มีรูปปก: แผนผังชั้น 1 (ถ้าไม่มีใช้ชั้นแรกที่มี)
               (SELECT fp.image_url FROM floor_plans fp WHERE fp.building_id = buildings.id
                ORDER BY fp.floor = '1' DESC, fp.floor LIMIT 1) AS floor_plan_image
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
        logActivity(req, {
            action: 'create', entity: 'building', entityId: results.insertId,
            detail: `เพิ่มอาคาร "${name.trim()}" (${code.trim()})`,
        });
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
        logActivity(req, {
            action: 'update', entity: 'building', entityId: Number(buildingId) || null,
            detail: `แก้ไขอาคาร "${name.trim()}" (${code.trim()})`,
        });
        res.json({ message: 'อัปเดตอาคารสำเร็จ!' });
    });
});

app.delete('/api/buildings/:id', requireAdmin, asyncRoute(async (req, res) => {
    const buildingId = req.params.id;
    const [buildings] = await pdb.query('SELECT name, cover_image FROM buildings WHERE id = ?', [buildingId]);
    const [floorPlans] = await pdb.query('SELECT image_url FROM floor_plans WHERE building_id = ?', [buildingId]);
    const [tourPoints] = await pdb.query('SELECT image_url FROM tour_points WHERE building_id = ?', [buildingId]);

    try {
        await pdb.query('DELETE FROM buildings WHERE id = ?', [buildingId]);
    } catch (err) {
        if (err.code === 'ER_ROW_IS_REFERENCED_2' || err.code === 'ER_ROW_IS_REFERENCED') {
            throw new HttpError(409, 'ลบไม่ได้ เพราะยังมีห้องเรียนอยู่ในอาคารนี้');
        }
        throw err;
    }

    // แผนผังชั้นและจุดเดินชมของอาคารถูกลบตามอัตโนมัติ (ON DELETE CASCADE) จึงลบไฟล์ที่อัปโหลดไว้ด้วย รวมทั้งรูปปก
    removeUploadedFiles([
        ...floorPlans.map(item => item.image_url),
        ...tourPoints.map(item => item.image_url),
        buildings[0]?.cover_image,
    ]);
    logActivity(req, {
        action: 'delete', entity: 'building', entityId: Number(buildingId) || null,
        detail: `ลบอาคาร "${buildings.length > 0 ? buildings[0].name : buildingId}"`,
    });
    res.json({ message: 'ลบอาคารสำเร็จ!' });
}));

// 🌟 รูปปกอาคาร (แสดงบนการ์ดอาคารในแอป) อัปโหลดใหม่ = แทนที่รูปเดิมและลบไฟล์เก่า 🌟
app.post('/api/admin/buildings/:id/cover', requireAdmin, handleUpload(coverUploader, 'image', 10), asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.params.id);
    if (buildingId === null) throw new HttpError(400, 'รหัสอาคารไม่ถูกต้อง');
    if (!req.file) throw new HttpError(400, 'กรุณาแนบไฟล์รูปปกอาคาร');

    const [buildings] = await pdb.query('SELECT name, cover_image FROM buildings WHERE id = ?', [buildingId]);
    if (buildings.length === 0) throw new HttpError(404, 'ไม่พบอาคารนี้ในระบบ');

    const saved = await saveUploadedImage(req.file, COVER_RULE);
    try {
        await pdb.query('UPDATE buildings SET cover_image = ? WHERE id = ?', [saved.url, buildingId]);
    } catch (err) {
        removeUploadedFiles([saved.url]);
        throw err;
    }
    removeUploadedFiles([buildings[0].cover_image]);

    logActivity(req, {
        action: 'upload', entity: 'building', entityId: buildingId,
        detail: `อัปโหลดรูปปกอาคาร "${buildings[0].name}" (${saved.width}x${saved.height})`,
    });
    res.json({ message: 'อัปโหลดรูปปกอาคารสำเร็จ!', cover_image: saved.url });
}));

app.delete('/api/admin/buildings/:id/cover', requireAdmin, asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.params.id);
    if (buildingId === null) throw new HttpError(400, 'รหัสอาคารไม่ถูกต้อง');

    const [buildings] = await pdb.query('SELECT name, cover_image FROM buildings WHERE id = ?', [buildingId]);
    if (buildings.length === 0) throw new HttpError(404, 'ไม่พบอาคารนี้ในระบบ');
    if (!buildings[0].cover_image) return res.json({ message: 'อาคารนี้ยังไม่มีรูปปก' });

    await pdb.query('UPDATE buildings SET cover_image = NULL WHERE id = ?', [buildingId]);
    removeUploadedFiles([buildings[0].cover_image]);
    logActivity(req, {
        action: 'delete', entity: 'building', entityId: buildingId,
        detail: `ลบรูปปกอาคาร "${buildings[0].name}"`,
    });
    res.json({ message: 'ลบรูปปกอาคารสำเร็จ!' });
}));

// ==========================================
// 🌟 API จัดการแผนผังชั้น (Floor Plans) 🌟
// ==========================================

function parsePositiveInt(value) {
    const num = Number(value);
    return Number.isInteger(num) && num > 0 ? num : null;
}

app.get('/api/admin/floorplans', requireAdmin, asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.query.building_id);
    const sql = `
        SELECT fp.id, fp.building_id, b.name AS building_name, fp.floor, fp.image_url, fp.width, fp.height, fp.updated_at,
               (SELECT COUNT(*) FROM rooms r WHERE r.building_id = fp.building_id AND r.floor = fp.floor) AS room_count,
               (SELECT COUNT(*) FROM rooms r WHERE r.building_id = fp.building_id AND r.floor = fp.floor
                   AND r.pin_x IS NOT NULL AND r.pin_y IS NOT NULL) AS pinned_count
        FROM floor_plans fp
        JOIN buildings b ON b.id = fp.building_id
        ${buildingId ? 'WHERE fp.building_id = ?' : ''}
        ORDER BY b.name, fp.floor
    `;
    const [rows] = await pdb.query(sql, buildingId ? [buildingId] : []);
    res.json(rows);
}));

app.post('/api/admin/floorplans', requireAdmin, handleUpload(floorPlanUploader, 'image', 10), asyncRoute(async (req, res) => {
    const body = req.body || {};
    const buildingId = parsePositiveInt(body.building_id);
    const floor = typeof body.floor === 'string' ? body.floor.trim() : '';

    if (buildingId === null) throw new HttpError(400, 'กรุณาเลือกอาคาร');
    if (floor === '') throw new HttpError(400, 'กรุณาระบุชั้น');
    if (floor.length > FLOOR_MAX_LENGTH) throw new HttpError(400, `ข้อมูลชั้นต้องไม่เกิน ${FLOOR_MAX_LENGTH} ตัวอักษร`);
    if (!req.file) throw new HttpError(400, 'กรุณาแนบไฟล์รูปแผนผังชั้น');

    const [buildings] = await pdb.query('SELECT name FROM buildings WHERE id = ?', [buildingId]);
    if (buildings.length === 0) throw new HttpError(400, 'ไม่พบอาคารนี้ในระบบ');
    const [existing] = await pdb.query('SELECT id FROM floor_plans WHERE building_id = ? AND floor = ?', [buildingId, floor]);
    if (existing.length > 0) {
        throw new HttpError(409, 'ชั้นนี้มีแผนผังอยู่แล้ว ให้ใช้ปุ่ม "เปลี่ยนรูป" แทน');
    }

    const saved = await saveUploadedImage(req.file, FLOORPLAN_RULE);
    let insertId;
    try {
        const [result] = await pdb.query(
            'INSERT INTO floor_plans (building_id, floor, image_url, width, height) VALUES (?, ?, ?, ?, ?)',
            [buildingId, floor, saved.url, saved.width, saved.height]
        );
        insertId = result.insertId;
    } catch (err) {
        removeUploadedFiles([saved.url]);
        if (err.code === 'ER_DUP_ENTRY') throw new HttpError(409, 'ชั้นนี้มีแผนผังอยู่แล้ว ให้ใช้ปุ่ม "เปลี่ยนรูป" แทน');
        throw err;
    }

    logActivity(req, {
        action: 'upload', entity: 'floor_plan', entityId: insertId,
        detail: `อัปโหลดแผนผัง ${buildings[0].name} ชั้น ${floor} (${saved.width}x${saved.height})`,
    });
    res.json({ message: 'อัปโหลดแผนผังชั้นสำเร็จ!', id: insertId, image_url: saved.url, width: saved.width, height: saved.height });
}));

app.put('/api/admin/floorplans/:id', requireAdmin, handleUpload(floorPlanUploader, 'image', 10), asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสแผนผังไม่ถูกต้อง');
    if (!req.file) throw new HttpError(400, 'กรุณาแนบไฟล์รูปแผนผังชั้น');

    const [plans] = await pdb.query(
        `SELECT fp.image_url, fp.floor, b.name AS building_name
         FROM floor_plans fp JOIN buildings b ON b.id = fp.building_id WHERE fp.id = ?`, [id]);
    if (plans.length === 0) throw new HttpError(404, 'ไม่พบแผนผังชั้นนี้');

    const saved = await saveUploadedImage(req.file, FLOORPLAN_RULE);
    try {
        await pdb.query('UPDATE floor_plans SET image_url = ?, width = ?, height = ? WHERE id = ?',
            [saved.url, saved.width, saved.height, id]);
    } catch (err) {
        removeUploadedFiles([saved.url]);
        throw err;
    }
    removeUploadedFiles([plans[0].image_url]);

    logActivity(req, {
        action: 'update', entity: 'floor_plan', entityId: id,
        detail: `เปลี่ยนรูปแผนผัง ${plans[0].building_name} ชั้น ${plans[0].floor} (${saved.width}x${saved.height})`,
    });
    res.json({ message: 'เปลี่ยนรูปแผนผังสำเร็จ!', image_url: saved.url, width: saved.width, height: saved.height });
}));

app.delete('/api/admin/floorplans/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสแผนผังไม่ถูกต้อง');

    const [plans] = await pdb.query(
        `SELECT fp.image_url, fp.floor, b.name AS building_name
         FROM floor_plans fp JOIN buildings b ON b.id = fp.building_id WHERE fp.id = ?`, [id]);
    if (plans.length === 0) throw new HttpError(404, 'ไม่พบแผนผังชั้นนี้');

    await pdb.query('DELETE FROM floor_plans WHERE id = ?', [id]);
    removeUploadedFiles([plans[0].image_url]);

    logActivity(req, {
        action: 'delete', entity: 'floor_plan', entityId: id,
        detail: `ลบแผนผัง ${plans[0].building_name} ชั้น ${plans[0].floor}`,
    });
    res.json({ message: 'ลบแผนผังชั้นสำเร็จ!' });
}));

// ==========================================
// 🌟 API ภาพพาโนรามา 360° และจุดเชื่อม (Panoramas & Hotspots) 🌟
// ==========================================

const ICON_TYPES = ['arrow', 'door', 'stairs', 'info'];
const POSITION_LABEL_MAX_LENGTH = 100;

// yaw = ตำแหน่งแนวนอนรอบภาพ (-180 ถึง 180 องศา), pitch = ตำแหน่งแนวตั้ง (-90 ถึง 90 องศา)
function validateHotspotInput({ yaw, pitch, icon_type, label }) {
    const yawNum = Number(yaw);
    const pitchNum = Number(pitch);
    if (yaw === null || yaw === undefined || yaw === '' || !Number.isFinite(yawNum) || yawNum < -180 || yawNum > 180) {
        return 'ค่า yaw ต้องเป็นตัวเลข -180 ถึง 180';
    }
    if (pitch === null || pitch === undefined || pitch === '' || !Number.isFinite(pitchNum) || pitchNum < -90 || pitchNum > 90) {
        return 'ค่า pitch ต้องเป็นตัวเลข -90 ถึง 90';
    }
    if (icon_type !== undefined && icon_type !== null && icon_type !== '' && !ICON_TYPES.includes(icon_type)) {
        return 'ประเภทไอคอนไม่ถูกต้อง';
    }
    if (label !== undefined && label !== null && String(label).length > POSITION_LABEL_MAX_LENGTH) {
        return `ป้ายชื่อจุดเชื่อมต้องไม่เกิน ${POSITION_LABEL_MAX_LENGTH} ตัวอักษร`;
    }
    return null;
}

// จุดเชื่อมต้องชี้ไปภาพอื่นที่อยู่ในห้องเดียวกันเท่านั้น
async function assertHotspotTarget(panoramaId, targetId) {
    if (targetId === null) return;
    if (targetId === panoramaId) {
        throw new HttpError(400, 'จุดเชื่อมต้องชี้ไปยังภาพอื่นในห้องเดียวกัน');
    }
    const [rows] = await pdb.query('SELECT id, room_id FROM panoramas WHERE id IN (?)', [[panoramaId, targetId]]);
    if (rows.length !== 2 || rows[0].room_id !== rows[1].room_id) {
        throw new HttpError(400, 'ภาพปลายทางต้องอยู่ในห้องเดียวกัน');
    }
}

function parseTargetPanoramaId(value) {
    if (value === null || value === undefined || value === '') return null;
    const id = parsePositiveInt(value);
    if (id === null) throw new HttpError(400, 'รหัสภาพปลายทางไม่ถูกต้อง');
    return id;
}

// รายการภาพพาโนรามาของห้อง พร้อมจุดเชื่อมทั้งหมด (คืน [] ถ้ายังไม่มีภาพ)
app.get('/api/rooms/:roomId/panoramas', asyncRoute(async (req, res) => {
    const roomId = parsePositiveInt(req.params.roomId);
    if (roomId === null) return res.json([]);

    const [panoramas] = await pdb.query(
        `SELECT id, room_id, image_url, position_label, sort_order, created_at
         FROM panoramas WHERE room_id = ? ORDER BY sort_order, id`, [roomId]);
    if (panoramas.length === 0) return res.json([]);

    const [hotspots] = await pdb.query(
        `SELECT id, panorama_id, target_panorama_id, yaw, pitch, icon_type, label
         FROM panorama_hotspots WHERE panorama_id IN (?) ORDER BY id`, [panoramas.map(item => item.id)]);

    const byPanorama = new Map();
    for (const hotspot of hotspots) {
        if (!byPanorama.has(hotspot.panorama_id)) byPanorama.set(hotspot.panorama_id, []);
        byPanorama.get(hotspot.panorama_id).push({ ...hotspot, yaw: Number(hotspot.yaw), pitch: Number(hotspot.pitch) });
    }
    res.json(panoramas.map(item => ({ ...item, hotspots: byPanorama.get(item.id) || [] })));
}));

app.post('/api/rooms/:roomId/panoramas', requireAdmin, handleUpload(panoramaUploader, 'image', 20), asyncRoute(async (req, res) => {
    const roomId = parsePositiveInt(req.params.roomId);
    if (roomId === null) throw new HttpError(400, 'รหัสห้องไม่ถูกต้อง');
    if (!req.file) throw new HttpError(400, 'กรุณาแนบไฟล์ภาพพาโนรามา');

    const body = req.body || {};
    const positionLabel = typeof body.position_label === 'string' ? body.position_label.trim() : '';
    if (positionLabel.length > POSITION_LABEL_MAX_LENGTH) {
        throw new HttpError(400, `ป้ายชื่อตำแหน่งต้องไม่เกิน ${POSITION_LABEL_MAX_LENGTH} ตัวอักษร`);
    }
    const sortOrder = Number.isInteger(Number(body.sort_order)) ? Number(body.sort_order) : 0;

    const [rooms] = await pdb.query('SELECT room_code FROM rooms WHERE id = ?', [roomId]);
    if (rooms.length === 0) throw new HttpError(400, 'ไม่พบห้องนี้ในระบบ');

    const saved = await saveUploadedImage(req.file, PANORAMA_RULE);
    let insertId;
    try {
        const [result] = await pdb.query(
            'INSERT INTO panoramas (room_id, image_url, position_label, sort_order) VALUES (?, ?, ?, ?)',
            [roomId, saved.url, positionLabel || null, sortOrder]);
        insertId = result.insertId;
    } catch (err) {
        removeUploadedFiles([saved.url]);
        throw err;
    }

    logActivity(req, {
        action: 'upload', entity: 'panorama', entityId: insertId,
        detail: `อัปโหลดภาพ 360° ห้อง "${rooms[0].room_code}"${positionLabel ? ` (${positionLabel})` : ''}`,
    });
    res.json({ message: 'อัปโหลดภาพพาโนรามาสำเร็จ!', id: insertId, image_url: saved.url });
}));

// แก้ไขป้ายชื่อ/ลำดับของภาพ (ถ้าจะเปลี่ยนไฟล์รูปให้ลบแล้วอัปโหลดใหม่)
app.put('/api/panoramas/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสภาพไม่ถูกต้อง');

    const { position_label: positionLabelRaw, sort_order: sortOrderRaw } = req.body || {};
    const positionLabel = typeof positionLabelRaw === 'string' ? positionLabelRaw.trim() : '';
    if (positionLabel.length > POSITION_LABEL_MAX_LENGTH) {
        throw new HttpError(400, `ป้ายชื่อตำแหน่งต้องไม่เกิน ${POSITION_LABEL_MAX_LENGTH} ตัวอักษร`);
    }
    const sortOrder = Number.isInteger(Number(sortOrderRaw)) ? Number(sortOrderRaw) : 0;

    const [result] = await pdb.query('UPDATE panoramas SET position_label = ?, sort_order = ? WHERE id = ?',
        [positionLabel || null, sortOrder, id]);
    if (result.affectedRows === 0) throw new HttpError(404, 'ไม่พบภาพพาโนรามานี้');

    logActivity(req, { action: 'update', entity: 'panorama', entityId: id, detail: `แก้ไขภาพ 360° #${id}` });
    res.json({ message: 'อัปเดตภาพพาโนรามาสำเร็จ!' });
}));

app.delete('/api/panoramas/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสภาพไม่ถูกต้อง');

    const [rows] = await pdb.query('SELECT image_url FROM panoramas WHERE id = ?', [id]);
    if (rows.length === 0) throw new HttpError(404, 'ไม่พบภาพพาโนรามานี้');

    await pdb.query('DELETE FROM panoramas WHERE id = ?', [id]);
    removeUploadedFiles([rows[0].image_url]);

    logActivity(req, { action: 'delete', entity: 'panorama', entityId: id, detail: `ลบภาพ 360° #${id}` });
    res.json({ message: 'ลบภาพพาโนรามาสำเร็จ!' });
}));

app.post('/api/panoramas/:panoramaId/hotspots', requireAdmin, asyncRoute(async (req, res) => {
    const panoramaId = parsePositiveInt(req.params.panoramaId);
    if (panoramaId === null) throw new HttpError(400, 'รหัสภาพไม่ถูกต้อง');

    const { target_panorama_id, yaw, pitch, icon_type, label } = req.body || {};
    const validationError = validateHotspotInput({ yaw, pitch, icon_type, label });
    if (validationError) throw new HttpError(400, validationError);

    const [panoramas] = await pdb.query('SELECT id FROM panoramas WHERE id = ?', [panoramaId]);
    if (panoramas.length === 0) throw new HttpError(404, 'ไม่พบภาพพาโนรามานี้');
    const targetId = parseTargetPanoramaId(target_panorama_id);
    await assertHotspotTarget(panoramaId, targetId);

    const [result] = await pdb.query(
        `INSERT INTO panorama_hotspots (panorama_id, target_panorama_id, yaw, pitch, icon_type, label)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [panoramaId, targetId, Number(yaw), Number(pitch), icon_type || 'arrow', label || null]);

    logActivity(req, {
        action: 'create', entity: 'hotspot', entityId: result.insertId,
        detail: `เพิ่มจุดเชื่อมในภาพ 360° #${panoramaId}${label ? ` (${label})` : ''}`,
    });
    res.json({ message: 'เพิ่มจุดเชื่อมสำเร็จ!', id: result.insertId });
}));

app.put('/api/hotspots/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสจุดเชื่อมไม่ถูกต้อง');

    const { target_panorama_id, yaw, pitch, icon_type, label } = req.body || {};
    const validationError = validateHotspotInput({ yaw, pitch, icon_type, label });
    if (validationError) throw new HttpError(400, validationError);

    const [hotspots] = await pdb.query('SELECT panorama_id FROM panorama_hotspots WHERE id = ?', [id]);
    if (hotspots.length === 0) throw new HttpError(404, 'ไม่พบจุดเชื่อมนี้');
    const targetId = parseTargetPanoramaId(target_panorama_id);
    await assertHotspotTarget(hotspots[0].panorama_id, targetId);

    await pdb.query(
        `UPDATE panorama_hotspots SET target_panorama_id = ?, yaw = ?, pitch = ?, icon_type = ?, label = ? WHERE id = ?`,
        [targetId, Number(yaw), Number(pitch), icon_type || 'arrow', label || null, id]);

    logActivity(req, { action: 'update', entity: 'hotspot', entityId: id, detail: `แก้ไขจุดเชื่อม #${id}` });
    res.json({ message: 'อัปเดตจุดเชื่อมสำเร็จ!' });
}));

app.delete('/api/hotspots/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสจุดเชื่อมไม่ถูกต้อง');

    const [result] = await pdb.query('DELETE FROM panorama_hotspots WHERE id = ?', [id]);
    if (result.affectedRows === 0) throw new HttpError(404, 'ไม่พบจุดเชื่อมนี้');

    logActivity(req, { action: 'delete', entity: 'hotspot', entityId: id, detail: `ลบจุดเชื่อม #${id}` });
    res.json({ message: 'ลบจุดเชื่อมสำเร็จ!' });
}));

// ==========================================
// 🌟 API เดินชมอาคาร 360° แบบ Street View (Tour points & links) 🌟
// ==========================================
// จุดถ่าย (tour_points) วางบนแผนผังชั้นเป็น % เหมือนหมุดห้อง heading = มุม (องศา) ที่หมุนภาพ
// ให้ทิศ "ขึ้น" ของแผนผังอยู่ที่ yaw 0 หน้าเดินชมจึงคำนวณทิศลูกศรจากตำแหน่งบนแผนผังได้เอง

const TOUR_IMAGE_MAX_WIDTH = 4096; // มือถือส่วนใหญ่แสดง texture ได้สูงสุด 4096 พิกเซล
const TOUR_LABEL_MAX_LENGTH = 100;
const TOUR_POINT_SELECT = `
    SELECT tp.id, tp.building_id, tp.floor, tp.image_url, tp.x, tp.y, tp.heading, tp.label, tp.room_id,
           r.room_code, tp.created_at
    FROM tour_points tp
    LEFT JOIN rooms r ON r.id = tp.room_id
`;

function formatTourPoint(row) {
    return {
        ...row,
        x: row.x === null ? null : Number(row.x),
        y: row.y === null ? null : Number(row.y),
        heading: Number(row.heading),
    };
}

// ภาพ 360° ต้องเป็นแบบ equirectangular (กว้าง:สูง = 2:1) ย่อให้กว้างไม่เกิน 4096 แล้วบันทึกเป็น JPG
async function saveTourImage(file) {
    let meta;
    try {
        meta = await sharp(file.buffer, { limitInputPixels: 20000 * 10000 }).metadata();
    } catch (err) {
        throw new HttpError(400, 'ไฟล์รูปไม่ถูกต้องหรือเสียหาย');
    }
    if (!['jpeg', 'png', 'webp'].includes(meta.format) || !meta.width || !meta.height) {
        throw new HttpError(400, IMAGE_TYPE_ERROR);
    }
    const ratio = meta.width / meta.height;
    if (ratio < 1.95 || ratio > 2.05) {
        throw new HttpError(400, `ภาพต้องเป็นภาพ 360° สัดส่วน 2:1 (ไฟล์นี้ ${meta.width}×${meta.height})`);
    }

    const fileName = `${TOUR_IMAGE_RULE.filePrefix}${crypto.randomBytes(8).toString('hex')}.jpg`;
    const info = await sharp(file.buffer, { limitInputPixels: 20000 * 10000 })
        .resize({ width: TOUR_IMAGE_MAX_WIDTH, withoutEnlargement: true })
        .jpeg({ quality: 85, mozjpeg: true })
        .toFile(path.join(TOUR_IMAGE_RULE.dir, fileName));
    return { url: `${TOUR_IMAGE_RULE.urlPrefix}${fileName}`, width: info.width, height: info.height };
}

function parsePercent(value, fieldName) {
    if (value === null || value === '') return null;
    const num = Number(value);
    if (!Number.isFinite(num) || num < 0 || num > 100) throw new HttpError(400, `${fieldName} ต้องเป็นตัวเลข 0 ถึง 100`);
    return Math.round(num * 1000) / 1000;
}

function normalizeHeading(value) {
    const num = Number(value);
    if (value === null || value === '' || !Number.isFinite(num)) throw new HttpError(400, 'ทิศของภาพต้องเป็นตัวเลข (องศา)');
    const wrapped = ((num % 360) + 540) % 360 - 180; // เก็บเป็น -180 ถึง 180
    return Math.round(wrapped * 1000) / 1000;
}

// อาคารที่มีจุดเดินชมวางบนแผนผังแล้ว (แท็บ "เดินชม" ในแอป)
app.get('/api/tour/buildings', asyncRoute(async (req, res) => {
    const [rows] = await pdb.query(`
        SELECT b.id, b.code, b.name, b.cover_image,
               COUNT(tp.id) AS point_count,
               COUNT(DISTINCT tp.floor) AS floor_count,
               (SELECT fp.image_url FROM floor_plans fp WHERE fp.building_id = b.id ORDER BY fp.floor LIMIT 1) AS floor_plan_image
        FROM buildings b
        JOIN tour_points tp ON tp.building_id = b.id AND tp.x IS NOT NULL AND tp.y IS NOT NULL
        GROUP BY b.id
        ORDER BY b.name
    `);
    res.json(rows);
}));

// ข้อมูลทัวร์ทั้งอาคารสำหรับหน้าเดินชม: แผนผังทุกชั้น จุดที่วางบนแผนผังแล้ว เส้นเชื่อม และหมุดห้อง (ใช้ทำป้ายห้องในภาพ)
app.get('/api/tour/:buildingId', asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.params.buildingId);
    if (buildingId === null) throw new HttpError(404, 'ไม่พบอาคารนี้');

    const [buildings] = await pdb.query('SELECT id, code, name FROM buildings WHERE id = ?', [buildingId]);
    if (buildings.length === 0) throw new HttpError(404, 'ไม่พบอาคารนี้');

    const [points] = await pdb.query(
        `${TOUR_POINT_SELECT} WHERE tp.building_id = ? AND tp.x IS NOT NULL AND tp.y IS NOT NULL ORDER BY tp.id`, [buildingId]);
    const ids = points.map(point => point.id);
    const [links] = ids.length === 0 ? [[]] : await pdb.query(
        'SELECT point_a, point_b FROM tour_links WHERE point_a IN (?) AND point_b IN (?) ORDER BY id', [ids, ids]);
    const [floors] = await pdb.query(
        'SELECT floor, image_url AS image, width, height FROM floor_plans WHERE building_id = ? ORDER BY floor', [buildingId]);
    const [rooms] = await pdb.query(
        `SELECT id, room_code, floor, pin_x, pin_y, status FROM rooms
         WHERE building_id = ? AND pin_x IS NOT NULL AND pin_y IS NOT NULL`, [buildingId]);

    res.json({
        building: buildings[0],
        floors,
        points: points.map(formatTourPoint),
        links: links.map(link => [link.point_a, link.point_b]),
        rooms: rooms.map(room => ({ ...room, pin_x: Number(room.pin_x), pin_y: Number(room.pin_y) })),
    });
}));

// แดชบอร์ด: ทุกจุดของอาคาร (รวมจุดที่ยังไม่ได้วางบนแผนผัง) พร้อมเส้นเชื่อม
app.get('/api/admin/tour/points', requireAdmin, asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.query.building_id);
    if (buildingId === null) throw new HttpError(400, 'กรุณาเลือกอาคาร');

    const [points] = await pdb.query(`${TOUR_POINT_SELECT} WHERE tp.building_id = ? ORDER BY tp.id`, [buildingId]);
    const ids = points.map(point => point.id);
    const [links] = ids.length === 0 ? [[]] : await pdb.query(
        'SELECT point_a, point_b FROM tour_links WHERE point_a IN (?) ORDER BY id', [ids]);
    res.json({ points: points.map(formatTourPoint), links: links.map(link => [link.point_a, link.point_b]) });
}));

app.post('/api/admin/tour/points', requireAdmin, handleUpload(tourImageUploader, 'image', 40), asyncRoute(async (req, res) => {
    const body = req.body || {};
    const buildingId = parsePositiveInt(body.building_id);
    const floor = typeof body.floor === 'string' ? body.floor.trim() : '';
    if (buildingId === null) throw new HttpError(400, 'กรุณาเลือกอาคาร');
    if (!floor || floor.length > FLOOR_MAX_LENGTH) throw new HttpError(400, 'กรุณาระบุชั้น');
    if (!req.file) throw new HttpError(400, 'กรุณาแนบไฟล์ภาพ 360°');

    const [buildings] = await pdb.query('SELECT name FROM buildings WHERE id = ?', [buildingId]);
    if (buildings.length === 0) throw new HttpError(400, 'ไม่พบอาคารนี้ในระบบ');

    const label = typeof body.label === 'string' ? body.label.trim().slice(0, TOUR_LABEL_MAX_LENGTH) : '';
    const saved = await saveTourImage(req.file);
    let insertId;
    try {
        const [result] = await pdb.query(
            'INSERT INTO tour_points (building_id, floor, image_url, label) VALUES (?, ?, ?, ?)',
            [buildingId, floor, saved.url, label || null]);
        insertId = result.insertId;
    } catch (err) {
        removeUploadedFiles([saved.url]);
        throw err;
    }

    logActivity(req, {
        action: 'upload', entity: 'tour_point', entityId: insertId,
        detail: `อัปโหลดจุดเดินชม ${buildings[0].name} ชั้น ${floor}${label ? ` (${label})` : ''}`,
    });
    const [rows] = await pdb.query(`${TOUR_POINT_SELECT} WHERE tp.id = ?`, [insertId]);
    res.json({ message: 'อัปโหลดภาพเดินชมสำเร็จ!', point: formatTourPoint(rows[0]) });
}));

// แก้ไขเฉพาะฟิลด์ที่ส่งมา: x, y (วาง/ย้ายบนแผนผัง), heading, label, room_id, floor
app.put('/api/admin/tour/points/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสจุดไม่ถูกต้อง');
    const [existing] = await pdb.query('SELECT building_id FROM tour_points WHERE id = ?', [id]);
    if (existing.length === 0) throw new HttpError(404, 'ไม่พบจุดเดินชมนี้');

    const body = req.body || {};
    const updates = {};
    if ('x' in body || 'y' in body) {
        const x = parsePercent(body.x ?? null, 'ตำแหน่ง x');
        const y = parsePercent(body.y ?? null, 'ตำแหน่ง y');
        if ((x === null) !== (y === null)) throw new HttpError(400, 'ต้องระบุตำแหน่ง x และ y คู่กัน');
        updates.x = x;
        updates.y = y;
    }
    if ('heading' in body) updates.heading = normalizeHeading(body.heading);
    if ('label' in body) {
        const label = typeof body.label === 'string' ? body.label.trim() : '';
        if (label.length > TOUR_LABEL_MAX_LENGTH) throw new HttpError(400, `ชื่อจุดต้องไม่เกิน ${TOUR_LABEL_MAX_LENGTH} ตัวอักษร`);
        updates.label = label || null;
    }
    if ('floor' in body) {
        const floor = typeof body.floor === 'string' ? body.floor.trim() : '';
        if (!floor || floor.length > FLOOR_MAX_LENGTH) throw new HttpError(400, 'กรุณาระบุชั้น');
        updates.floor = floor;
    }
    if ('room_id' in body) {
        if (body.room_id === null || body.room_id === '') {
            updates.room_id = null;
        } else {
            const roomId = parsePositiveInt(body.room_id);
            const [rooms] = roomId === null ? [[]] : await pdb.query(
                'SELECT id FROM rooms WHERE id = ? AND building_id = ?', [roomId, existing[0].building_id]);
            if (rooms.length === 0) throw new HttpError(400, 'ห้องที่เลือกต้องอยู่ในอาคารเดียวกัน');
            updates.room_id = roomId;
        }
    }
    if (Object.keys(updates).length === 0) throw new HttpError(400, 'ไม่มีข้อมูลที่จะแก้ไข');

    await pdb.query('UPDATE tour_points SET ? WHERE id = ?', [updates, id]);
    logActivity(req, { action: 'update', entity: 'tour_point', entityId: id, detail: `แก้ไขจุดเดินชม #${id}` });
    const [rows] = await pdb.query(`${TOUR_POINT_SELECT} WHERE tp.id = ?`, [id]);
    res.json({ message: 'บันทึกจุดเดินชมสำเร็จ!', point: formatTourPoint(rows[0]) });
}));

app.delete('/api/admin/tour/points/:id', requireAdmin, asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสจุดไม่ถูกต้อง');
    const [rows] = await pdb.query('SELECT image_url FROM tour_points WHERE id = ?', [id]);
    if (rows.length === 0) throw new HttpError(404, 'ไม่พบจุดเดินชมนี้');

    await pdb.query('DELETE FROM tour_points WHERE id = ?', [id]); // เส้นเชื่อมถูกลบตาม (ON DELETE CASCADE)
    removeUploadedFiles([rows[0].image_url]);
    logActivity(req, { action: 'delete', entity: 'tour_point', entityId: id, detail: `ลบจุดเดินชม #${id}` });
    res.json({ message: 'ลบจุดเดินชมสำเร็จ!' });
}));

// เส้นเชื่อมเดินได้ทั้งไปและกลับ เก็บแบบ point_a < point_b ข้ามชั้นได้ (เช่น บันได) แต่ต้องอยู่อาคารเดียวกัน
async function parseTourLink(body) {
    const a = parsePositiveInt(body?.point_a);
    const b = parsePositiveInt(body?.point_b);
    if (a === null || b === null || a === b) throw new HttpError(400, 'กรุณาเลือกจุดสองจุดที่ต่างกัน');
    const [rows] = await pdb.query('SELECT id, building_id FROM tour_points WHERE id IN (?)', [[a, b]]);
    if (rows.length !== 2) throw new HttpError(404, 'ไม่พบจุดเดินชม');
    if (rows[0].building_id !== rows[1].building_id) throw new HttpError(400, 'เชื่อมได้เฉพาะจุดในอาคารเดียวกัน');
    return [Math.min(a, b), Math.max(a, b)];
}

app.post('/api/admin/tour/links', requireAdmin, asyncRoute(async (req, res) => {
    const [a, b] = await parseTourLink(req.body);
    await pdb.query('INSERT IGNORE INTO tour_links (point_a, point_b) VALUES (?, ?)', [a, b]);
    logActivity(req, { action: 'create', entity: 'tour_link', detail: `เชื่อมจุดเดินชม #${a} ↔ #${b}` });
    res.json({ message: 'เชื่อมจุดสำเร็จ!' });
}));

app.delete('/api/admin/tour/links', requireAdmin, asyncRoute(async (req, res) => {
    const [a, b] = await parseTourLink(req.body);
    const [result] = await pdb.query('DELETE FROM tour_links WHERE point_a = ? AND point_b = ?', [a, b]);
    if (result.affectedRows === 0) throw new HttpError(404, 'ไม่พบเส้นเชื่อมนี้');
    logActivity(req, { action: 'delete', entity: 'tour_link', detail: `ตัดเส้นเชื่อม #${a} ↔ #${b}` });
    res.json({ message: 'ตัดเส้นเชื่อมสำเร็จ!' });
}));

// เชื่อมอัตโนมัติในชั้นเดียว: ทุกจุดเชื่อมกับจุดที่ใกล้ที่สุด และจุดใกล้อื่น ๆ ที่อยู่คนละทิศ
// (ระบบไม่รู้ว่ากำแพงอยู่ตรงไหน จึงอาจได้เส้นที่ทะลุผนัง ผู้ดูแลตัดออกเองได้) เพิ่มอย่างเดียว ไม่ลบเส้นเดิม
const AUTOLINK_MAX_PER_POINT = 4;
const AUTOLINK_MIN_ANGLE = 50; // องศา
const AUTOLINK_DISTANCE_FACTOR = 2.2; // ไม่เชื่อมจุดที่ไกลกว่าจุดใกล้สุดเกินกี่เท่า

function autoLinkPairs(points) {
    const pairs = new Set();
    for (const point of points) {
        const others = points
            .filter(other => other !== point)
            .map(other => ({
                other,
                distance: Math.hypot(other.px - point.px, other.py - point.py),
                angle: Math.atan2(other.px - point.px, point.py - other.py) * 180 / Math.PI,
            }))
            .sort((p, q) => p.distance - q.distance);
        if (others.length === 0) continue;

        const chosen = [];
        for (const candidate of others) {
            if (chosen.length >= AUTOLINK_MAX_PER_POINT) break;
            if (candidate.distance > others[0].distance * AUTOLINK_DISTANCE_FACTOR) break;
            const sameDirection = chosen.some(item => {
                const diff = Math.abs((((candidate.angle - item.angle) % 360) + 540) % 360 - 180);
                return diff < AUTOLINK_MIN_ANGLE;
            });
            if (!sameDirection) chosen.push(candidate);
        }
        for (const { other } of chosen) {
            pairs.add(`${Math.min(point.id, other.id)}-${Math.max(point.id, other.id)}`);
        }
    }
    return [...pairs].map(key => key.split('-').map(Number));
}

app.post('/api/admin/tour/autolink', requireAdmin, asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.body?.building_id);
    const floor = typeof req.body?.floor === 'string' ? req.body.floor.trim() : '';
    if (buildingId === null || !floor) throw new HttpError(400, 'กรุณาเลือกอาคารและชั้น');

    const [plans] = await pdb.query(
        'SELECT width, height FROM floor_plans WHERE building_id = ? AND floor = ?', [buildingId, floor]);
    const width = plans[0]?.width || 1;
    const height = plans[0]?.height || 1;
    const [rows] = await pdb.query(
        'SELECT id, x, y FROM tour_points WHERE building_id = ? AND floor = ? AND x IS NOT NULL AND y IS NOT NULL',
        [buildingId, floor]);
    // ระยะต้องคิดเป็นพิกเซลของแผนผัง (x, y เป็น % ของด้านกว้าง/สูงซึ่งยาวไม่เท่ากัน)
    const points = rows.map(row => ({ id: row.id, px: Number(row.x) * width / 100, py: Number(row.y) * height / 100 }));

    let added = 0;
    for (const [a, b] of autoLinkPairs(points)) {
        const [result] = await pdb.query('INSERT IGNORE INTO tour_links (point_a, point_b) VALUES (?, ?)', [a, b]);
        added += result.affectedRows;
    }
    logActivity(req, { action: 'create', entity: 'tour_link', detail: `เชื่อมจุดเดินชมอัตโนมัติ ชั้น ${floor} (${added} เส้น)` });
    res.json({ message: `เชื่อมอัตโนมัติแล้ว ${added} เส้น`, added });
}));

// ==========================================
// 🌟 ส่งออก / นำเข้าห้องเรียนด้วยไฟล์ CSV 🌟
// ==========================================

const CSV_HEADER = ['building_code', 'room_code', 'floor', 'room_type', 'capacity', 'status', 'seats', 'outlets', 'ac', 'wifi', 'pin_x', 'pin_y'];
const CSV_IMPORT_MAX_ROWS = 2000;
const AMENITY_INT_COLUMNS = ['seats', 'outlets', 'ac'];
const AMENITY_COLUMNS = [...AMENITY_INT_COLUMNS, 'wifi'];
const WIFI_MAX_LENGTH = 100;

function csvCell(value) {
    if (value === null || value === undefined) return '';
    const text = String(value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

app.get('/api/admin/rooms/export.csv', requireAdmin, asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.query.building_id);
    const sql = `
        SELECT b.code AS building_code, r.room_code, r.floor, r.room_type, r.capacity, r.status, r.amenities, r.pin_x, r.pin_y
        FROM rooms r JOIN buildings b ON b.id = r.building_id
        ${buildingId ? 'WHERE b.id = ?' : ''}
        ORDER BY b.code, r.floor, r.room_code
    `;
    const [rows] = await pdb.query(sql, buildingId ? [buildingId] : []);

    const lines = [CSV_HEADER.join(',')];
    for (const row of rows) {
        const amenities = row.amenities && typeof row.amenities === 'object' ? row.amenities : {};
        lines.push([
            row.building_code, row.room_code, row.floor, row.room_type, row.capacity, row.status,
            amenities.seats, amenities.outlets, amenities.ac, amenities.wifi, row.pin_x, row.pin_y,
        ].map(csvCell).join(','));
    }

    const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="rooms-${stamp}.csv"`);
    // BOM ทำให้ Excel อ่านภาษาไทยได้ถูกต้อง
    res.send('﻿' + lines.join('\r\n') + '\r\n');

    logActivity(req, { action: 'export', entity: 'room', detail: `ส่งออกห้องเรียนเป็น CSV ${rows.length} ห้อง` });
}));

function parseImportCsv(text) {
    let headerCols = [];
    let records;
    try {
        records = parseCsv(text, {
            bom: true,
            trim: true,
            skip_empty_lines: true,
            columns: (header) => {
                headerCols = header.map(name => String(name).trim().toLowerCase());
                return headerCols;
            },
        });
    } catch (err) {
        throw new HttpError(400, `ไฟล์ CSV ไม่ถูกต้อง: ${err.message}`);
    }
    return { headerCols, records };
}

// ตรวจและแปลงข้อมูลแต่ละแถวเป็นแผนงาน (สร้างใหม่/อัปเดต) โดยยังไม่แตะฐานข้อมูล
async function planRoomImport(text) {
    const { headerCols, records } = parseImportCsv(text);

    const buildingColumn = headerCols.includes('building_code') ? 'building_code' : (headerCols.includes('building') ? 'building' : null);
    if (buildingColumn === null || !headerCols.includes('room_code') || !headerCols.includes('floor')) {
        throw new HttpError(400, 'ไฟล์ CSV ต้องมีคอลัมน์ building_code, room_code และ floor');
    }
    if (records.length === 0) throw new HttpError(400, 'ไฟล์ CSV ไม่มีข้อมูลห้องเรียน');
    if (records.length > CSV_IMPORT_MAX_ROWS) {
        throw new HttpError(400, `นำเข้าได้ครั้งละไม่เกิน ${CSV_IMPORT_MAX_ROWS} แถว`);
    }

    const has = (column) => headerCols.includes(column);
    const [buildings] = await pdb.query('SELECT id, code, name FROM buildings');
    const buildingByKey = new Map();
    for (const building of buildings) {
        buildingByKey.set(building.code.toLowerCase(), building);
        if (!buildingByKey.has(building.name.toLowerCase())) buildingByKey.set(building.name.toLowerCase(), building);
    }
    const [existingRooms] = await pdb.query('SELECT id, building_id, room_code FROM rooms');
    const existingByKey = new Map(existingRooms.map(room => [`${room.building_id}|${room.room_code.toLowerCase()}`, room.id]));

    const seenKeys = new Map();
    const items = records.map((record, index) => {
        const rowNumber = index + 2; // แถวที่ 1 คือหัวตาราง
        const errors = [];
        const item = { row: rowNumber, room_code: record.room_code || '', building: record[buildingColumn] || '', errors, action: null };

        const building = buildingByKey.get(String(record[buildingColumn] || '').toLowerCase());
        if (!building) errors.push(`ไม่พบอาคาร "${record[buildingColumn] || ''}"`);

        const blankToNull = (value) => (value === undefined || value === '' ? null : value);
        const fields = {};
        if (has('room_type')) fields.room_type = blankToNull(record.room_type);
        if (has('capacity')) fields.capacity = blankToNull(record.capacity) === null ? null : Number(record.capacity);
        if (has('status')) fields.status = blankToNull(record.status) || 'active';
        if (has('pin_x')) fields.pin_x = blankToNull(record.pin_x) === null ? null : Number(record.pin_x);
        if (has('pin_y')) fields.pin_y = blankToNull(record.pin_y) === null ? null : Number(record.pin_y);

        if (AMENITY_COLUMNS.some(has)) {
            const amenities = {};
            for (const column of AMENITY_INT_COLUMNS) {
                const value = has(column) ? blankToNull(record[column]) : null;
                if (value === null) continue;
                const num = Number(value);
                if (!Number.isInteger(num) || num < 0) errors.push(`${column} ต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป`);
                else amenities[column] = num;
            }
            const wifi = has('wifi') ? blankToNull(record.wifi) : null;
            if (wifi !== null) {
                if (wifi.length > WIFI_MAX_LENGTH) errors.push(`wifi ต้องไม่เกิน ${WIFI_MAX_LENGTH} ตัวอักษร`);
                else amenities.wifi = wifi;
            }
            fields.amenities = Object.keys(amenities).length > 0 ? amenities : null;
        }

        const validationError = validateRoomInput({
            room_code: record.room_code, building_name: building ? building.name : 'x', floor: record.floor,
            pin_x: fields.pin_x, pin_y: fields.pin_y, room_type: fields.room_type,
            capacity: fields.capacity, status: fields.status, amenities: fields.amenities,
        });
        if (validationError) errors.push(validationError);

        if (building && !validationError) {
            const key = `${building.id}|${record.room_code.trim().toLowerCase()}`;
            if (seenKeys.has(key)) {
                errors.push(`ซ้ำกับแถวที่ ${seenKeys.get(key)} ในไฟล์เดียวกัน`);
            } else {
                seenKeys.set(key, rowNumber);
                item.existingId = existingByKey.get(key) || null;
                item.action = item.existingId ? 'update' : 'create';
            }
            item.building = building.name;
            item.building_id = building.id;
            item.room_code = record.room_code.trim();
            item.floor = record.floor.trim();
            item.fields = fields;
        }
        return item;
    });

    return { items };
}

app.post('/api/admin/rooms/import', requireAdmin, asyncRoute(async (req, res) => {
    const { csv, dry_run: dryRun } = req.body || {};
    if (typeof csv !== 'string' || csv.trim() === '') {
        throw new HttpError(400, 'กรุณาเลือกไฟล์ CSV');
    }

    const { items } = await planRoomImport(csv);
    const errorCount = items.filter(item => item.errors.length > 0).length;
    const summary = {
        total: items.length,
        create: items.filter(item => item.errors.length === 0 && item.action === 'create').length,
        update: items.filter(item => item.errors.length === 0 && item.action === 'update').length,
        errors: errorCount,
    };
    const preview = items.map(item => ({
        row: item.row, room_code: item.room_code, building: item.building, action: item.action, errors: item.errors,
    }));

    if (dryRun) {
        return res.json({ dry_run: true, can_import: errorCount === 0, summary, rows: preview });
    }
    if (errorCount > 0) {
        return res.status(400).json({
            error: `พบข้อผิดพลาด ${errorCount} แถว จึงไม่มีข้อมูลถูกนำเข้า กรุณาแก้ไขไฟล์แล้วลองใหม่`,
            dry_run: false, can_import: false, summary, rows: preview,
        });
    }

    // นำเข้าแบบทั้งหมดหรือไม่เลย (transaction) ถ้าแถวใดล้มเหลวจะย้อนกลับทั้งหมด
    const conn = await pdb.getConnection();
    try {
        await conn.beginTransaction();
        for (const item of items) {
            const f = item.fields;
            if (item.action === 'create') {
                await conn.query(
                    `INSERT INTO rooms (room_code, building_id, floor, room_type, capacity, status, amenities, pin_x, pin_y)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [item.room_code, item.building_id, item.floor, f.room_type ?? null, f.capacity ?? null,
                        f.status || 'active', f.amenities ? JSON.stringify(f.amenities) : null, f.pin_x ?? null, f.pin_y ?? null]);
            } else {
                const sets = ['floor = ?'];
                const values = [item.floor];
                if ('room_type' in f) { sets.push('room_type = ?'); values.push(f.room_type); }
                if ('capacity' in f) { sets.push('capacity = ?'); values.push(f.capacity); }
                if ('status' in f) { sets.push('status = ?'); values.push(f.status); }
                if ('amenities' in f) { sets.push('amenities = ?'); values.push(f.amenities ? JSON.stringify(f.amenities) : null); }
                if ('pin_x' in f) { sets.push('pin_x = ?'); values.push(f.pin_x); }
                if ('pin_y' in f) { sets.push('pin_y = ?'); values.push(f.pin_y); }
                await conn.query(`UPDATE rooms SET ${sets.join(', ')} WHERE id = ?`, [...values, item.existingId]);
            }
        }
        await conn.commit();
    } catch (err) {
        await conn.rollback();
        throw err;
    } finally {
        conn.release();
    }

    logActivity(req, {
        action: 'import', entity: 'room',
        detail: `นำเข้า CSV: เพิ่ม ${summary.create} ห้อง, อัปเดต ${summary.update} ห้อง (จาก ${summary.total} แถว)`,
    });
    res.json({ message: `นำเข้าสำเร็จ: เพิ่ม ${summary.create} ห้อง, อัปเดต ${summary.update} ห้อง`, dry_run: false, can_import: true, summary });
}));

// ==========================================
// 🌟 System Logs และสรุปภาพรวม (Overview) 🌟
// ==========================================

app.get('/api/admin/logs', requireAdmin, asyncRoute(async (req, res) => {
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

    const where = [];
    const params = [];
    for (const column of ['entity', 'action']) {
        if (typeof req.query[column] === 'string' && req.query[column] !== '') {
            where.push(`${column} = ?`);
            params.push(req.query[column]);
        }
    }
    if (typeof req.query.q === 'string' && req.query.q.trim() !== '') {
        where.push('(detail LIKE ? OR username LIKE ?)');
        params.push(`%${req.query.q.trim()}%`, `%${req.query.q.trim()}%`);
    }
    const whereSql = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';

    const [[countRow]] = await pdb.query(`SELECT COUNT(*) AS total FROM activity_logs ${whereSql}`, params);
    const [rows] = await pdb.query(
        `SELECT id, action, entity, entity_id, detail, username, ip, created_at
         FROM activity_logs ${whereSql} ORDER BY id DESC LIMIT ? OFFSET ?`,
        [...params, limit, offset]);
    res.json({ total: countRow.total, limit, offset, rows });
}));

// สรุปสถิติภาพรวมสำหรับหน้า Overview ของ Admin Dashboard
app.get('/api/admin/overview', requireAdmin, asyncRoute(async (req, res) => {
    const [[stats]] = await pdb.query(`
        SELECT
            (SELECT COUNT(*) FROM buildings) AS building_count,
            (SELECT COUNT(*) FROM rooms) AS room_count,
            (SELECT COUNT(*) FROM rooms WHERE status = 'active') AS active_room_count,
            (SELECT COUNT(*) FROM rooms WHERE status = 'maintenance') AS maintenance_room_count,
            (SELECT COUNT(DISTINCT room_id) FROM panoramas) AS rooms_with_panorama_count,
            (SELECT COUNT(*) FROM rooms WHERE pin_x IS NOT NULL AND pin_y IS NOT NULL) AS pinned_room_count,
            (SELECT COUNT(*) FROM floor_plans) AS floor_plan_count
    `);
    const [recentActivity] = await pdb.query(
        'SELECT id, action, entity, detail, username, created_at FROM activity_logs ORDER BY id DESC LIMIT 5');
    res.json({ ...stats, recent_activity: recentActivity });
}));

// ข้อผิดพลาดที่ไม่ได้ดักไว้ (เช่น JSON เสียรูป, body ใหญ่เกิน) ให้ตอบเป็น JSON เสมอ
app.use((err, req, res, next) => {
    if (err && err.type === 'entity.too.large') {
        return res.status(413).json({ error: 'ข้อมูลที่ส่งมามีขนาดใหญ่เกินไป' });
    }
    if (err && err.type === 'entity.parse.failed') {
        return res.status(400).json({ error: 'รูปแบบข้อมูล JSON ไม่ถูกต้อง' });
    }
    console.error(err);
    res.status(err && err.status ? err.status : 500).json({ error: 'เกิดข้อผิดพลาดภายในระบบ' });
});

// ==========================================
// 🌟 สร้างตารางของแดชบอร์ดให้เองตอนเริ่มระบบ (รองรับฐานข้อมูลเดิมที่สร้างไว้ก่อนมีฟีเจอร์นี้) 🌟
// ==========================================
// ต้องตรงกับส่วน "Dashboard tables" ใน db/init.sql ทุกตารางใช้ IF NOT EXISTS จึงรันซ้ำได้ปลอดภัย
const DASHBOARD_TABLES = [
    `CREATE TABLE IF NOT EXISTS floor_plans (
        id INT NOT NULL AUTO_INCREMENT,
        building_id INT NOT NULL,
        floor VARCHAR(50) NOT NULL,
        image_url VARCHAR(500) NOT NULL,
        width INT NOT NULL,
        height INT NOT NULL,
        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_floor_plans_building_floor (building_id, floor),
        CONSTRAINT fk_floor_plans_building FOREIGN KEY (building_id) REFERENCES buildings (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS panoramas (
        id INT NOT NULL AUTO_INCREMENT,
        room_id INT NOT NULL,
        image_url VARCHAR(500) NOT NULL,
        position_label VARCHAR(100) DEFAULT NULL,
        sort_order INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY fk_panoramas_room (room_id),
        CONSTRAINT fk_panoramas_room FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS panorama_hotspots (
        id INT NOT NULL AUTO_INCREMENT,
        panorama_id INT NOT NULL,
        target_panorama_id INT DEFAULT NULL,
        yaw DECIMAL(7,3) NOT NULL,
        pitch DECIMAL(7,3) NOT NULL,
        icon_type VARCHAR(30) NOT NULL DEFAULT 'arrow',
        label VARCHAR(100) DEFAULT NULL,
        PRIMARY KEY (id),
        KEY fk_hotspots_panorama (panorama_id),
        KEY fk_hotspots_target (target_panorama_id),
        CONSTRAINT fk_hotspots_panorama FOREIGN KEY (panorama_id) REFERENCES panoramas (id) ON DELETE CASCADE,
        CONSTRAINT fk_hotspots_target FOREIGN KEY (target_panorama_id) REFERENCES panoramas (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS activity_logs (
        id BIGINT NOT NULL AUTO_INCREMENT,
        action VARCHAR(30) NOT NULL,
        entity VARCHAR(30) NOT NULL,
        entity_id INT DEFAULT NULL,
        detail VARCHAR(500) DEFAULT NULL,
        username VARCHAR(100) DEFAULT NULL,
        ip VARCHAR(64) DEFAULT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_activity_logs_created (created_at),
        KEY idx_activity_logs_entity_action (entity, action)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS admin_settings (
        setting_key VARCHAR(50) NOT NULL,
        setting_value TEXT NOT NULL,
        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS tour_points (
        id INT NOT NULL AUTO_INCREMENT,
        building_id INT NOT NULL,
        floor VARCHAR(50) NOT NULL,
        image_url VARCHAR(500) NOT NULL,
        x DECIMAL(6,3) DEFAULT NULL,
        y DECIMAL(6,3) DEFAULT NULL,
        heading DECIMAL(7,3) NOT NULL DEFAULT 0,
        label VARCHAR(100) DEFAULT NULL,
        room_id INT DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_tour_points_building_floor (building_id, floor),
        KEY fk_tour_points_room (room_id),
        CONSTRAINT fk_tour_points_building FOREIGN KEY (building_id) REFERENCES buildings (id) ON DELETE CASCADE,
        CONSTRAINT fk_tour_points_room FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS tour_links (
        id INT NOT NULL AUTO_INCREMENT,
        point_a INT NOT NULL,
        point_b INT NOT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_tour_links_pair (point_a, point_b),
        KEY fk_tour_links_b (point_b),
        CONSTRAINT fk_tour_links_a FOREIGN KEY (point_a) REFERENCES tour_points (id) ON DELETE CASCADE,
        CONSTRAINT fk_tour_links_b FOREIGN KEY (point_b) REFERENCES tour_points (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
];

// แผนผัง LH3 เดิมที่เคยฝังไว้ในโค้ด ย้ายมาเป็นข้อมูลในตาราง (ใส่ครั้งเดียวตอนสร้างตารางใหม่ เพื่อไม่ให้แผนผังที่ลบทิ้งแล้วกลับมาอีก)
const SEED_FLOOR_PLANS = [
    ['1', '/floorplans/lh3-floor-1.png', 1506, 1045],
    ['2', '/floorplans/lh3-floor-2.png', 1516, 1037],
    ['3', '/floorplans/lh3-floor-3.png', 1498, 1050],
];

async function ensureDashboardSchema(attempt = 1) {
    try {
        const [existing] = await pdb.query("SHOW TABLES LIKE 'floor_plans'");
        const floorPlansIsNew = existing.length === 0;

        for (const statement of DASHBOARD_TABLES) {
            await pdb.query(statement);
        }
        // คอลัมน์รูปปกอาคาร เพิ่มให้ฐานข้อมูลเดิมที่สร้างก่อนมีฟีเจอร์นี้
        const [coverColumn] = await pdb.query("SHOW COLUMNS FROM buildings LIKE 'cover_image'");
        if (coverColumn.length === 0) {
            await pdb.query('ALTER TABLE buildings ADD COLUMN cover_image VARCHAR(500) DEFAULT NULL');
        }
        if (floorPlansIsNew) {
            for (const [floor, imageUrl, width, height] of SEED_FLOOR_PLANS) {
                await pdb.query(
                    `INSERT IGNORE INTO floor_plans (building_id, floor, image_url, width, height)
                     SELECT id, ?, ?, ?, ? FROM buildings WHERE code = 'LH3'`,
                    [floor, imageUrl, width, height]);
            }
        }
        console.log('✅ ตารางของแดชบอร์ดพร้อมใช้งาน');
    } catch (err) {
        // MySQL อาจยังเริ่มไม่เสร็จตอน docker compose up ครั้งแรก จึงลองใหม่เป็นระยะ
        if (attempt >= 30) {
            console.error('❌ สร้างตารางของแดชบอร์ดไม่สำเร็จ:', err.message);
            return;
        }
        if (attempt === 1) console.warn('⏳ รอฐานข้อมูลพร้อมเพื่อสร้างตารางของแดชบอร์ด...', err.message);
        setTimeout(() => ensureDashboardSchema(attempt + 1), 2000);
    }
}

// 4. สั่งให้เซิร์ฟเวอร์เปิดทำงาน
app.listen(port, () => {
    console.log(`🚀 Server เปิดทำงานแล้วที่ http://localhost:${port}`);
    ensureDashboardSchema();
});
