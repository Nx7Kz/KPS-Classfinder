const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const os = require('node:os');
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
const QRCode = require('qrcode');
const archiver = require('archiver');
const yauzl = require('yauzl');

const app = express();
const port = 3000;

app.disable('x-powered-by'); // ไม่ต้องบอกคนนอกว่าใช้ Express (ลดข้อมูลที่ช่วยคนโจมตีเดา exploit)
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
const DB_CONFIG = {
    host: 'db',
    user: 'root',
    password: '',
    database: 'kps_classfinder',
};
const db = mysql.createPool({
    ...DB_CONFIG,
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
// 🌟 บัญชีผู้ดูแลและสิทธิ์การใช้งาน (RBAC) 🌟
// ==========================================
// ค่า ADMIN_* / EDITOR_* จาก environment ใช้เป็นบัญชีตั้งต้นแค่ครั้งแรกที่ตาราง admin_users ยังว่าง
// หลังจากนั้นบัญชีทั้งหมดจัดการจากหน้า Settings > ผู้ดูแลและสิทธิ์การใช้งาน
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD_HASH
    || bcrypt.hashSync(process.env.ADMIN_PASSWORD || 'admin1234', 10);
const EDITOR_USERNAME = process.env.EDITOR_USERNAME || 'editor';
const EDITOR_PASSWORD_HASH = process.env.EDITOR_PASSWORD_HASH
    || bcrypt.hashSync(process.env.EDITOR_PASSWORD || 'editor1234', 10);
const DUMMY_PASSWORD_HASH = bcrypt.hashSync('timing-equalizer', 10); // เทียบรหัสกับค่านี้เมื่อไม่พบ username เพื่อไม่ให้จับเวลาแล้วเดาชื่อผู้ใช้ได้
const PASSWORD_MIN_LENGTH = 8;
const PASSWORD_MAX_BYTES = 72; // bcrypt ใช้เพียง 72 ไบต์แรกของรหัสผ่าน

// สิทธิ์ย่อยของแต่ละโมดูล (ตรงกับ checkbox ในหน้ากำหนดสิทธิ์บทบาท) — requires = สิทธิ์ที่ต้องมีควบคู่กัน (เช่น แก้ไขได้ต้องดูได้ด้วย)
const PERMISSION_MODULES = [
    {
        key: 'overview', icon: 'bar_chart', label: 'ภาพรวมและสถิติ (Overview)', description: 'สรุปจำนวนอาคาร ห้อง และสถานะระบบ',
        permissions: [{ key: 'overview.view', label: 'เข้าดูแดชบอร์ด (View)' }],
    },
    {
        key: 'buildings', icon: 'apartment', label: 'อาคารและห้องเรียน (Buildings & Rooms)', description: 'ฐานข้อมูลอาคาร ห้อง การปักหมุดพิกัด และรูปปกอาคาร',
        permissions: [
            { key: 'buildings.read', label: 'ดูข้อมูล (Read)' },
            { key: 'buildings.create', label: 'เพิ่ม/แก้ไข/ปักหมุด (Create/Edit)', requires: ['buildings.read'] },
            { key: 'buildings.delete', label: 'ลบข้อมูล (Delete)', requires: ['buildings.read'], danger: true },
            { key: 'buildings.csv', label: 'นำเข้า/ส่งออก CSV', requires: ['buildings.read'] },
        ],
    },
    {
        key: 'floorplans', icon: 'map', label: 'แผนผังชั้น (Floor Plans)', description: 'รูปแผนผังชั้นของแต่ละอาคาร',
        permissions: [
            { key: 'floorplans.read', label: 'ดูแผนผัง (Read)' },
            { key: 'floorplans.write', label: 'อัปโหลด/เปลี่ยนผังชั้น (Write)', requires: ['floorplans.read'] },
            { key: 'floorplans.delete', label: 'ลบไฟล์แผนผัง (Delete)', requires: ['floorplans.read'], danger: true },
        ],
    },
    {
        key: 'panoramas', icon: 'photo_camera', label: 'ภาพ 360° และจุดเชื่อม (Panorama Editor)', description: 'ภาพพาโนรามา Hotspots และเส้นทางเดินชม',
        permissions: [
            { key: 'panoramas.read', label: 'ดูภาพ 360° (Read)' },
            { key: 'panoramas.upload', label: 'อัปโหลดภาพ 360° (Upload)', requires: ['panoramas.read'] },
            { key: 'panoramas.hotspots', label: 'แก้ไขจุดเชื่อม Hotspot', requires: ['panoramas.read'] },
            { key: 'panoramas.delete', label: 'ลบภาพ 360° (Delete)', requires: ['panoramas.read'], danger: true },
        ],
    },
    {
        key: 'logs', icon: 'schedule', label: 'บันทึกเหตุการณ์ระบบ (System Logs)', description: 'ประวัติการเข้าสู่ระบบและการแก้ไขข้อมูล',
        permissions: [
            { key: 'logs.own', label: 'ดูบันทึกของตนเอง' },
            { key: 'logs.all', label: 'ดูบันทึกของทุกบัญชี + ส่งออก CSV', requires: ['logs.own'] },
        ],
    },
    {
        key: 'settings', icon: 'settings', label: 'การตั้งค่าและผู้ดูแล (Settings & Admin Roles)', description: 'จัดการบัญชีผู้ดูแลและสิทธิ์บทบาท',
        permissions: [{ key: 'settings.manage', label: 'จัดการผู้ดูแลและบทบาท', locked: true }],
    },
];
const PERMISSION_DEFS = new Map(PERMISSION_MODULES.flatMap(module => module.permissions.map(permission => [permission.key, permission])));
// สิทธิ์จัดการผู้ดูแล/บทบาทมีเฉพาะบทบาท admin เท่านั้น มอบให้บทบาทอื่นไม่ได้
const GRANTABLE_PERMISSIONS = [...PERMISSION_DEFS.values()].filter(permission => !permission.locked).map(permission => permission.key);
const ALL_PERMISSIONS = [...PERMISSION_DEFS.keys()];
const SUPER_ROLE = 'admin';

// กรองเฉพาะสิทธิ์ที่มีจริงและมอบได้ แล้วเติมสิทธิ์ที่ต้องมีควบคู่ให้ครบ
function normalizePermissions(list) {
    const granted = new Set(Array.isArray(list) ? list.filter(key => GRANTABLE_PERMISSIONS.includes(key)) : []);
    let changed = true;
    while (changed) {
        changed = false;
        for (const key of [...granted]) {
            for (const required of PERMISSION_DEFS.get(key).requires || []) {
                if (!granted.has(required)) { granted.add(required); changed = true; }
            }
        }
    }
    return [...granted];
}

// บทบาทตั้งต้น 4 บทบาท (is_system) ใส่ลงฐานข้อมูลครั้งแรก หลังจากนั้นแก้ไขได้จากหน้า Settings
const DEFAULT_ROLES = [
    {
        key: 'admin', label: 'Super Admin', label_th: 'ผู้ดูแลระบบสูงสุด',
        description: 'ทำได้ทุกอย่างในระบบ รวมถึงเพิ่ม ระงับ และกำหนดสิทธิ์บัญชีผู้ดูแลคนอื่น (แก้ไขสิทธิ์ของบทบาทนี้ไม่ได้)',
        permissions: ALL_PERMISSIONS,
    },
    {
        key: 'building_manager', label: 'Building Manager', label_th: 'ผู้จัดการอาคารและห้อง',
        description: 'ดูแลและปรับปรุงข้อมูลอาคาร ห้องเรียน แผนผังชั้น และพิกัดหมุดห้องเรียน ดูภาพ 360° ได้อย่างเดียว',
        permissions: ['overview.view', 'buildings.read', 'buildings.create', 'buildings.delete', 'buildings.csv',
            'floorplans.read', 'floorplans.write', 'floorplans.delete', 'panoramas.read', 'logs.own'],
    },
    {
        key: 'panorama_editor', label: 'Panorama Editor', label_th: 'ผู้ดูแลภาพ 360° และรูปภาพ',
        description: 'อัปโหลดภาพ 360° แผนผังชั้น และแก้จุดเชื่อมต่อ (Hotspots) ดูข้อมูลอาคาร/ห้องได้อย่างเดียว',
        permissions: ['overview.view', 'buildings.read', 'floorplans.read', 'floorplans.write', 'floorplans.delete',
            'panoramas.read', 'panoramas.upload', 'panoramas.hotspots', 'panoramas.delete', 'logs.own'],
    },
    {
        key: 'auditor', label: 'Auditor / Viewer', label_th: 'เจ้าหน้าที่ตรวจสอบ',
        description: 'ดูได้ทุกหน้ารวมถึงบันทึกระบบของทุกคน แต่แก้ไขหรือลบข้อมูลไม่ได้',
        permissions: ['overview.view', 'buildings.read', 'floorplans.read', 'panoramas.read', 'logs.own', 'logs.all'],
    },
];
const DEFAULT_ROLE_BY_KEY = new Map(DEFAULT_ROLES.map(role => [role.key, role]));
const ROLE_KEY_PATTERN = /^[a-z][a-z0-9_]{2,29}$/;
const USER_STATUSES = ['active', 'suspended'];
const USERNAME_PATTERN = /^[a-z0-9][a-z0-9._-]{2,29}$/;

// บทบาททั้งหมดเก็บในหน่วยความจำ (โหลดจาก admin_roles ตอนเริ่มระบบและทุกครั้งที่แก้ไข) เพื่อไม่ต้อง query ทุกคำขอ
let rolesCache = new Map();
async function reloadRoles() {
    const [rows] = await pdb.query('SELECT role_key, label, label_th, description, permissions, is_system FROM admin_roles ORDER BY is_system DESC, created_at, role_key');
    const next = new Map();
    for (const row of rows) {
        let stored = [];
        try { stored = JSON.parse(row.permissions); } catch (err) { stored = []; }
        // บทบาท admin ได้สิทธิ์ครบเสมอ ไม่ขึ้นกับค่าในฐานข้อมูล กันล็อกตัวเองออกจากระบบ
        const permissions = row.role_key === SUPER_ROLE ? ALL_PERMISSIONS : normalizePermissions(stored);
        next.set(row.role_key, {
            key: row.role_key, label: row.label, label_th: row.label_th, description: row.description,
            permissions: new Set(permissions), is_system: Boolean(row.is_system),
        });
    }
    rolesCache = next;
}
async function ensureRolesLoaded() {
    if (rolesCache.size === 0) await reloadRoles();
}
function hasPermission(role, ...permissionKeys) {
    const permissions = rolesCache.get(role)?.permissions;
    return Boolean(permissions) && permissionKeys.some(key => permissions.has(key));
}
function roleLabelTh(role) {
    return rolesCache.get(role)?.label_th || rolesCache.get(role)?.label || role;
}

// ==========================================
// 🌟 นโยบายความปลอดภัย (Security & 2FA) 🌟
// ==========================================
const SECURITY_DEFAULTS = {
    require_2fa: false, // บังคับให้ทุกบัญชีเปิด 2FA (บัญชีที่ยังไม่เปิดต้องตั้งค่าก่อนใช้งานส่วนอื่น)
    password_min_length: 8,
    password_complexity: false, // ต้องมีตัวพิมพ์ใหญ่ เล็ก ตัวเลข และอักขระพิเศษ
    password_expiry_days: 0, // 0 = ไม่หมดอายุ
    session_timeout_minutes: 480, // หมดเวลาเมื่อไม่มีการใช้งาน
    account_lockout: true, // ล็อกบัญชีชั่วคราวเมื่อใส่รหัสผิดติดกัน
    ip_allowlist_enabled: false, // จำกัดการเข้าสู่ระบบจัดการเฉพาะ IP ในรายการ
    ip_allowlist: [], // [{ cidr, note }]
};
const SECURITY_CHOICES = {
    password_min_length: [8, 10, 12],
    password_expiry_days: [0, 60, 90, 180],
    session_timeout_minutes: [15, 30, 60, 240, 480],
};
const SECURITY_SETTING_KEY = 'security_settings';
const LOCKOUT_MAX_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;
const IP_ALLOWLIST_MAX = 50;
const TWO_FACTOR_ISSUER = 'KPS ClassFinder';
const BACKUP_CODE_COUNT = 10;
const TWO_FACTOR_PENDING_MS = 5 * 60 * 1000;
const TWO_FACTOR_MAX_ATTEMPTS = 5;

let securitySettings = { ...SECURITY_DEFAULTS };

// ตัดค่าที่ไม่รู้จัก/นอกช่วงทิ้ง แล้วเติมค่าตั้งต้นให้ครบ (ใช้ทั้งตอนโหลดจากฐานข้อมูลและตอนรับค่าจากหน้าเว็บ)
function sanitizeSecuritySettings(input, base = SECURITY_DEFAULTS) {
    const source = input && typeof input === 'object' ? input : {};
    const result = { ...base };
    for (const key of ['require_2fa', 'password_complexity', 'account_lockout', 'ip_allowlist_enabled']) {
        if (typeof source[key] === 'boolean') result[key] = source[key];
    }
    for (const [key, choices] of Object.entries(SECURITY_CHOICES)) {
        const value = Number(source[key]);
        if (choices.includes(value)) result[key] = value;
    }
    const list = Array.isArray(source.ip_allowlist) ? source.ip_allowlist : [];
    result.ip_allowlist = list.slice(0, IP_ALLOWLIST_MAX).map((item) => ({
        cidr: typeof item?.cidr === 'string' ? item.cidr.trim() : '',
        note: typeof item?.note === 'string' ? item.note.trim().slice(0, 100) : '',
    })).filter(item => parseAllowEntry(item.cidr) !== null);
    return result;
}

async function reloadSecuritySettings() {
    const [rows] = await pdb.query('SELECT setting_value FROM admin_settings WHERE setting_key = ?', [SECURITY_SETTING_KEY]);
    let stored = {};
    if (rows.length > 0) {
        try { stored = JSON.parse(rows[0].setting_value); } catch (err) { stored = {}; }
    }
    securitySettings = sanitizeSecuritySettings(stored);
}

// ----- IP allow-list (รองรับ IPv4 แบบ x.x.x.x และ x.x.x.x/n กับ IPv6 แบบตรงตัว) -----
function normalizeIp(ip) {
    return String(ip || '').replace(/^::ffff:/, '');
}
function parseIpv4(text) {
    const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(text);
    if (!match) return null;
    const parts = match.slice(1).map(Number);
    if (parts.some(part => part > 255)) return null;
    return ((parts[0] * 16777216) + (parts[1] * 65536) + (parts[2] * 256) + parts[3]) >>> 0;
}
function parseAllowEntry(raw) {
    if (typeof raw !== 'string') return null;
    const text = raw.trim();
    const [addressText, prefixText] = text.split('/');
    const v4 = parseIpv4(addressText);
    if (v4 !== null) {
        const prefix = prefixText === undefined ? 32 : Number(prefixText);
        if (!Number.isInteger(prefix) || prefix < 0 || prefix > 32 || (prefixText !== undefined && !/^\d+$/.test(prefixText))) return null;
        const mask = prefix === 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) >>> 0;
        return { kind: 'v4', base: (v4 & mask) >>> 0, mask };
    }
    if (prefixText === undefined && /^[0-9a-fA-F:]+$/.test(text) && text.includes(':')) return { kind: 'exact', value: text.toLowerCase() };
    return null;
}
function isIpAllowed(ip, list = securitySettings.ip_allowlist) {
    const address = normalizeIp(ip);
    const v4 = parseIpv4(address);
    return list.some((item) => {
        const entry = parseAllowEntry(item.cidr);
        if (!entry) return false;
        if (entry.kind === 'v4') return v4 !== null && ((v4 & entry.mask) >>> 0) === entry.base;
        return address.toLowerCase() === entry.value;
    });
}
// ใช้กับหน้า login และ API ผู้ดูแล เท่านั้น (API สาธารณะที่แอปมือถือใช้ไม่ถูกจำกัด)
function ipGate(req, res, next) {
    if (!securitySettings.ip_allowlist_enabled || isIpAllowed(req.ip)) return next();
    res.status(403).json({ error: `ระบบจัดการอนุญาตเฉพาะเครือข่ายที่กำหนด (IP ของคุณ: ${normalizeIp(req.ip)})`, code: 'IP_BLOCKED' });
}

// ----- TOTP (RFC 6238: HMAC-SHA1, 6 หลัก, ทุก 30 วินาที — ใช้ได้กับ Google Authenticator / Microsoft Authenticator / Authy) -----
const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function base32Encode(buffer) {
    let bits = 0; let value = 0; let output = '';
    for (const byte of buffer) {
        value = (value << 8) | byte; bits += 8;
        while (bits >= 5) { output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31]; bits -= 5; }
    }
    if (bits > 0) output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
    return output;
}
function base32Decode(text) {
    let bits = 0; let value = 0; const bytes = [];
    for (const char of text.replace(/=+$/, '').toUpperCase()) {
        const index = BASE32_ALPHABET.indexOf(char);
        if (index < 0) continue;
        value = (value << 5) | index; bits += 5;
        if (bits >= 8) { bytes.push((value >>> (bits - 8)) & 255); bits -= 8; }
    }
    return Buffer.from(bytes);
}
function hotp(secret, counter) {
    const message = Buffer.alloc(8);
    message.writeBigUInt64BE(BigInt(counter));
    const digest = crypto.createHmac('sha1', secret).update(message).digest();
    const offset = digest[19] & 0xf;
    const code = (((digest[offset] & 0x7f) << 24) | (digest[offset + 1] << 16) | (digest[offset + 2] << 8) | digest[offset + 3]) % 1000000;
    return String(code).padStart(6, '0');
}
// คืนเลขช่วงเวลา (step) ที่ตรงกับรหัส หรือ null ถ้าไม่ตรง — ไม่รับ step ที่เคยใช้แล้ว (lastStep) กันการใช้รหัสซ้ำ
function verifyTotp(secretBase32, code, lastStep = 0) {
    const clean = String(code || '').replace(/\s/g, '');
    if (!/^\d{6}$/.test(clean)) return null;
    const secret = base32Decode(secretBase32);
    const now = Math.floor(Date.now() / 30000);
    for (const delta of [0, -1, 1]) {
        const step = now + delta;
        if (step <= lastStep) continue;
        if (crypto.timingSafeEqual(Buffer.from(hotp(secret, step)), Buffer.from(clean))) return step;
    }
    return null;
}

// ----- รหัสสำรองฉุกเฉิน (เก็บเป็น bcrypt hash ใช้ได้ครั้งเดียว) -----
async function generateBackupCodes() {
    const plain = Array.from({ length: BACKUP_CODE_COUNT }, () => {
        const raw = crypto.randomBytes(5).toString('hex');
        return `${raw.slice(0, 5)}-${raw.slice(5)}`;
    });
    const hashes = await Promise.all(plain.map(code => bcrypt.hash(code, 8)));
    return { plain, hashes };
}
function parseBackupHashes(stored) {
    try { const list = JSON.parse(stored || '[]'); return Array.isArray(list) ? list : []; } catch (err) { return []; }
}
async function consumeBackupCode(user, input) {
    const normalized = String(input || '').trim().toLowerCase();
    if (!/^[0-9a-f]{5}-?[0-9a-f]{5}$/.test(normalized)) return false;
    const code = normalized.includes('-') ? normalized : `${normalized.slice(0, 5)}-${normalized.slice(5)}`;
    const hashes = parseBackupHashes(user.backup_codes);
    for (let index = 0; index < hashes.length; index += 1) {
        if (await bcrypt.compare(code, hashes[index])) {
            hashes.splice(index, 1);
            await pdb.query('UPDATE admin_users SET backup_codes = ? WHERE id = ?', [JSON.stringify(hashes), user.id]);
            return true;
        }
    }
    return false;
}

// ล็อกบัญชีชั่วคราวเมื่อใส่รหัสผิดติดกัน (นับทั้งรหัสผ่านและรหัส 2FA)
async function registerFailedAttempt(userId) {
    if (!securitySettings.account_lockout) return;
    await pdb.query('UPDATE admin_users SET failed_attempts = failed_attempts + 1 WHERE id = ?', [userId]);
    await pdb.query(
        `UPDATE admin_users SET locked_until = DATE_ADD(NOW(), INTERVAL ${LOCKOUT_MINUTES} MINUTE), failed_attempts = 0
         WHERE id = ? AND failed_attempts >= ?`, [userId, LOCKOUT_MAX_ATTEMPTS]);
}

// สิ่งที่บัญชีนี้ต้องทำก่อนใช้งานต่อ: เปิด 2FA (ถ้าระบบบังคับ) หรือเปลี่ยนรหัสผ่านที่หมดอายุ
function computeRestrictions(user) {
    const restrictions = [];
    if (securitySettings.require_2fa && !user.totp_enabled) restrictions.push('2fa_setup');
    const days = securitySettings.password_expiry_days;
    if (days > 0 && user.password_changed_at && Date.now() - new Date(user.password_changed_at).getTime() > days * 86400000) {
        restrictions.push('password_expired');
    }
    return restrictions;
}

// ผู้ใช้ปัจจุบันของ session ดึงจากฐานข้อมูลทุกคำขอ เพื่อให้การระงับบัญชี ลบบัญชี หรือเปลี่ยนบทบาทมีผลทันที
async function loadSessionUser(req) {
    const id = req.session?.userId;
    if (!id) return null;
    await ensureRolesLoaded();
    const [rows] = await pdb.query(
        'SELECT id, username, role, status, full_name, totp_enabled, password_changed_at FROM admin_users WHERE id = ?', [id]);
    const user = rows[0];
    if (!user || user.status !== 'active' || !rolesCache.has(user.role)) return null;
    user.restrictions = computeRestrictions(user);
    return user;
}

function guard(isAllowed, { allowRestricted = false } = {}) {
    return async (req, res, next) => {
        const user = await loadSessionUser(req);
        if (!user) {
            if (req.session?.userId) req.session.destroy(() => {});
            return res.status(401).json({ error: 'กรุณาเข้าสู่ระบบก่อนทำรายการนี้' });
        }
        if (!allowRestricted && user.restrictions.length > 0) {
            return res.status(403).json({
                error: user.restrictions.includes('2fa_setup') ? 'ระบบบังคับใช้ 2FA กรุณาตั้งค่าการยืนยันตัวตน 2 ขั้นตอนก่อนใช้งาน' : 'รหัสผ่านหมดอายุ กรุณาเปลี่ยนรหัสผ่านก่อนใช้งาน',
                code: 'RESTRICTED', restrictions: user.restrictions,
            });
        }
        if (!isAllowed(user.role)) {
            return res.status(403).json({ error: 'บัญชีนี้ไม่มีสิทธิ์ทำรายการนี้' });
        }
        req.user = user;
        next();
    };
}
// requireAuth: เข้าสู่ระบบแล้วก็พอ  |  requireAnyUser: เหมือน requireAuth แต่ใช้ได้แม้ติดเงื่อนไข (ตั้งค่า 2FA / เปลี่ยนรหัสผ่านหมดอายุ)
// requirePerm(...keys): ต้องมีสิทธิ์ย่อยอย่างน้อยหนึ่งข้อที่ระบุ
const requireAuth = guard(() => true);
const requireAnyUser = guard(() => true, { allowRestricted: true });
const requirePerm = (...permissionKeys) => guard(role => hasPermission(role, ...permissionKeys));

function sessionPayload(user) {
    const role = rolesCache.get(user.role);
    return {
        role: user.role,
        role_label: role.label_th || role.label,
        username: user.username,
        full_name: user.full_name || '',
        permissions: [...role.permissions],
        totp_enabled: Boolean(user.totp_enabled),
        restrictions: user.restrictions || [],
    };
}

// ไฟล์สาธารณะ (อัปโหลดจากแดชบอร์ด + ไลบรารีหน้าเดินชม) ไม่เกี่ยวกับการเข้าสู่ระบบ จึงให้ Express เสิร์ฟ
// ก่อนลงทะเบียน session middleware เพื่อไม่ให้ทุกคำขอไฟล์สถิตย์ต้องผ่านการตรวจ/สร้าง session โดยไม่จำเป็น
const PUBLIC_DIR = path.join(__dirname, 'public');
const FLOORPLAN_DIR = path.join(PUBLIC_DIR, 'floorplans');
const PANORAMA_DIR = path.join(PUBLIC_DIR, 'panoramas');
const COVER_DIR = path.join(PUBLIC_DIR, 'covers');
const TOUR_IMAGE_DIR = path.join(PUBLIC_DIR, 'tour-images');
fs.mkdirSync(FLOORPLAN_DIR, { recursive: true });
fs.mkdirSync(PANORAMA_DIR, { recursive: true });
fs.mkdirSync(COVER_DIR, { recursive: true });
fs.mkdirSync(TOUR_IMAGE_DIR, { recursive: true });

app.use(express.static(PUBLIC_DIR));

// ไลบรารีของหน้าเดินชม (Photo Sphere Viewer + three.js) เสิร์ฟจาก node_modules ไม่ต้องพึ่ง CDN
const NODE_MODULES_DIR = path.join(__dirname, 'node_modules');
app.use('/vendor/three', express.static(path.join(NODE_MODULES_DIR, 'three', 'build')));
for (const name of ['core', 'virtual-tour-plugin', 'map-plugin', 'markers-plugin']) {
    app.use(`/vendor/psv/${name}`, express.static(path.join(NODE_MODULES_DIR, '@photo-sphere-viewer', name)));
}

// ==========================================
// 🌟 ตั้งค่าระบบ (การประมวลผลภาพ 360° ที่อัปโหลด + จำกัดคำขอ API) 🌟
// ==========================================
const SYSTEM_DEFAULTS = {
    convert_webp: false, // แปลงภาพ 360° ที่อัปโหลดใหม่เป็น WebP
    max_width: 8192, // ย่อภาพ 360° ที่กว้างกว่านี้ (พิกเซล)
    quality: 85, // คุณภาพการบีบอัด (60-100)
    api_rate_limit: 600, // จำนวนคำขอ API ต่อ IP ต่อนาที (0 = ไม่จำกัด) ไม่นับผู้ที่ล็อกอินเป็นผู้ดูแล
};
const SYSTEM_CHOICES = { max_width: [2048, 4096, 8192], api_rate_limit: [0, 120, 300, 600, 1200] };
const SYSTEM_SETTING_KEY = 'system_settings';
let systemSettings = { ...SYSTEM_DEFAULTS };

function sanitizeSystemSettings(input, base = SYSTEM_DEFAULTS) {
    const source = input && typeof input === 'object' ? input : {};
    const result = { ...base };
    if (typeof source.convert_webp === 'boolean') result.convert_webp = source.convert_webp;
    for (const [key, choices] of Object.entries(SYSTEM_CHOICES)) {
        const value = Number(source[key]);
        if (choices.includes(value)) result[key] = value;
    }
    const quality = Number(source.quality);
    if (Number.isInteger(quality) && quality >= 60 && quality <= 100) result.quality = quality;
    return result;
}

async function reloadSystemSettings() {
    const [rows] = await pdb.query('SELECT setting_value FROM admin_settings WHERE setting_key = ?', [SYSTEM_SETTING_KEY]);
    let stored = {};
    if (rows.length > 0) {
        try { stored = JSON.parse(rows[0].setting_value); } catch (err) { stored = {}; }
    }
    systemSettings = sanitizeSystemSettings(stored);
}

// จำกัดคำขอ API ต่อ IP (ค่าตั้งได้ที่ Settings > ระบบและพื้นที่จัดเก็บ) ผู้ดูแลที่ล็อกอินแล้วและหน้า login (มีตัวจำกัดของตัวเอง) ไม่ถูกนับ
const apiLimiter = rateLimit({
    windowMs: 60 * 1000,
    limit: () => systemSettings.api_rate_limit || Number.MAX_SAFE_INTEGER,
    standardHeaders: true,
    legacyHeaders: false,
    skip: req => systemSettings.api_rate_limit === 0 || Boolean(req.session?.userId) || req.path.startsWith('/login'),
    message: { error: 'ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่' },
});

const sessionStore = new session.MemoryStore();
app.use(session({
    store: sessionStore,
    secret: process.env.SESSION_SECRET || 'kps-classfinder-dev-secret',
    resave: false,
    saveUninitialized: false,
    rolling: true, // ต่ออายุ session ทุกครั้งที่ใช้งาน (หมดอายุเมื่อไม่มีการใช้งานตามเวลาที่ผู้ดูแลตั้ง)
    cookie: {
        httpOnly: true,
        maxAge: 8 * 60 * 60 * 1000, // ค่าเริ่มต้นสำหรับ session ที่ยังไม่ล็อกอิน
    },
}));
// ผู้ที่ล็อกอินแล้วใช้เวลาหมดอายุตามนโยบายความปลอดภัย (Settings > ความปลอดภัย)
app.use((req, res, next) => {
    if (req.session?.userId) req.session.cookie.maxAge = securitySettings.session_timeout_minutes * 60 * 1000;
    next();
});
// จำกัด IP เฉพาะหน้า login และ API ผู้ดูแล (API สาธารณะของแอปมือถือไม่ถูกจำกัด)
app.use(['/api/login', '/api/admin'], ipGate);
app.use('/api', apiLimiter);

// ==========================================
// 🌟 บันทึกกิจกรรม (System Logs) 🌟
// ==========================================
// " (label)" ต่อท้ายข้อความ log ถ้ามีป้ายชื่อ ไม่งั้นว่างเปล่า (แยกออกมาเพื่อไม่ต้องซ้อน template literal)
function labelSuffix(label) {
    return label ? ` (${label})` : '';
}

// fire-and-forget: ถ้าบันทึกไม่สำเร็จ จะไม่ทำให้คำสั่งหลักล้มเหลว และห้ามใส่รหัสผ่าน/ข้อมูลลับใน detail
function logActivity(req, { action, entity, entityId = null, detail = null, username = null }) {
    const actor = username || req.user?.username || null;
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

function clientIp(req) {
    return normalizeIp(req.ip).slice(0, 64);
}

// เริ่ม session ใหม่ของผู้ใช้ (หมุนรหัส session กัน session fixation) แล้วบันทึกการเข้าสู่ระบบ
async function completeLogin(req, res, user, detail) {
    await new Promise((resolve, reject) => req.session.regenerate(err => (err ? reject(err) : resolve())));
    req.session.userId = user.id;
    await pdb.query(
        'UPDATE admin_users SET last_login_at = NOW(), last_login_ip = ?, failed_attempts = 0, locked_until = NULL WHERE id = ?',
        [clientIp(req), user.id]);
    logActivity(req, { action: 'login', entity: 'session', username: user.username, detail });
    const fresh = await loadSessionUser(req);
    res.json({ message: 'เข้าสู่ระบบสำเร็จ', ...sessionPayload(fresh) });
}

app.post('/api/login', loginLimiter, asyncRoute(async (req, res) => {
    const { username, password } = req.body || {};

    const rejectLogin = (detail = 'ล็อกอินไม่สำเร็จ') => {
        logActivity(req, {
            action: 'login_failed', entity: 'session', detail,
            username: typeof username === 'string' ? username : null,
        });
        return res.status(401).json({ error: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });
    };

    if (typeof username !== 'string' || typeof password !== 'string') {
        return rejectLogin();
    }
    const [rows] = await pdb.query(
        `SELECT id, username, password_hash, role, status, full_name, totp_enabled, failed_attempts, locked_until
         FROM admin_users WHERE username = ?`, [username.trim().toLowerCase()]);
    const user = rows[0];
    const passwordOk = bcrypt.compareSync(password, user ? user.password_hash : DUMMY_PASSWORD_HASH);

    if (user && securitySettings.account_lockout && user.locked_until && new Date(user.locked_until) > new Date()) {
        const minutes = Math.max(1, Math.ceil((new Date(user.locked_until) - Date.now()) / 60000));
        logActivity(req, { action: 'login_failed', entity: 'session', detail: 'บัญชีถูกล็อกชั่วคราว', username: user.username });
        return res.status(423).json({ error: `บัญชีนี้ถูกล็อกชั่วคราวเพราะใส่รหัสผ่านผิดหลายครั้ง ลองใหม่ในอีก ${minutes} นาที` });
    }
    if (!user || !passwordOk || !rolesCache.has(user.role)) {
        if (user) await registerFailedAttempt(user.id);
        return rejectLogin();
    }
    if (user.status !== 'active') {
        return rejectLogin('บัญชีนี้ถูกระงับ');
    }

    if (user.totp_enabled) {
        // รหัสผ่านถูกแล้ว แต่ยังไม่ถือว่าเข้าสู่ระบบ จนกว่าจะยืนยันรหัส 2FA (ภายใน 5 นาที)
        await new Promise((resolve, reject) => req.session.regenerate(err => (err ? reject(err) : resolve())));
        req.session.pending2fa = { userId: user.id, attempts: 0, expires: Date.now() + TWO_FACTOR_PENDING_MS };
        return res.json({ needs_2fa: true, message: 'กรอกรหัส 6 หลักจากแอป Authenticator เพื่อเข้าสู่ระบบ' });
    }
    await completeLogin(req, res, user, `เข้าสู่ระบบสำเร็จ (${roleLabelTh(user.role)})`);
}));

app.post('/api/login/2fa', loginLimiter, asyncRoute(async (req, res) => {
    const pending = req.session?.pending2fa;
    if (!pending || pending.expires < Date.now()) {
        throw new HttpError(401, 'หมดเวลายืนยันรหัส 2FA กรุณาเข้าสู่ระบบใหม่อีกครั้ง');
    }
    const [rows] = await pdb.query(
        `SELECT id, username, role, status, full_name, totp_secret, totp_enabled, totp_last_step, backup_codes
         FROM admin_users WHERE id = ?`, [pending.userId]);
    const user = rows[0];
    if (!user || user.status !== 'active' || !user.totp_enabled || !rolesCache.has(user.role)) {
        throw new HttpError(401, 'บัญชีนี้ไม่สามารถเข้าสู่ระบบได้');
    }

    const code = typeof req.body?.code === 'string' ? req.body.code.trim() : '';
    let method = null;
    const step = verifyTotp(user.totp_secret, code, Number(user.totp_last_step) || 0);
    if (step !== null) {
        method = 'Authenticator';
        await pdb.query('UPDATE admin_users SET totp_last_step = ? WHERE id = ?', [step, user.id]);
    } else if (await consumeBackupCode(user, code)) {
        method = 'รหัสสำรองฉุกเฉิน';
    }
    if (method === null) {
        pending.attempts += 1;
        await registerFailedAttempt(user.id);
        logActivity(req, { action: 'login_failed', entity: 'session', detail: 'รหัส 2FA ไม่ถูกต้อง', username: user.username });
        if (pending.attempts >= TWO_FACTOR_MAX_ATTEMPTS) {
            delete req.session.pending2fa;
            throw new HttpError(401, 'ใส่รหัส 2FA ผิดหลายครั้ง กรุณาเข้าสู่ระบบใหม่อีกครั้ง');
        }
        throw new HttpError(401, 'รหัส 2FA ไม่ถูกต้องหรือหมดอายุ');
    }
    await completeLogin(req, res, user, `เข้าสู่ระบบสำเร็จด้วย 2FA (${method})`);
}));

app.post('/api/logout', asyncRoute(async (req, res) => {
    const user = await loadSessionUser(req);
    if (user) {
        logActivity(req, { action: 'logout', entity: 'session', detail: 'ออกจากระบบ', username: user.username });
    }
    req.session.destroy(() => {
        res.json({ message: 'ออกจากระบบแล้ว' });
    });
}));

app.get('/api/session', asyncRoute(async (req, res) => {
    const user = await loadSessionUser(req);
    if (!user) return res.json({ isAdmin: false, role: null, username: null });
    res.json({ isAdmin: user.role === 'admin', ...sessionPayload(user) });
}));

// ตรวจรหัสผ่านใหม่ตามนโยบาย (ใช้ทั้งตอนเปลี่ยนรหัสของตัวเอง สร้างบัญชี และรีเซ็ตรหัส)
function assertValidNewPassword(newPassword) {
    const minLength = Math.max(PASSWORD_MIN_LENGTH, securitySettings.password_min_length);
    if (typeof newPassword !== 'string' || newPassword.length < minLength) {
        throw new HttpError(400, `รหัสผ่านใหม่ต้องยาวอย่างน้อย ${minLength} ตัวอักษร`);
    }
    if (Buffer.byteLength(newPassword, 'utf8') > PASSWORD_MAX_BYTES) {
        throw new HttpError(400, `รหัสผ่านใหม่ยาวเกินไป (ไม่เกิน ${PASSWORD_MAX_BYTES} ไบต์)`);
    }
    if (securitySettings.password_complexity
        && !(/[a-z]/.test(newPassword) && /[A-Z]/.test(newPassword) && /\d/.test(newPassword) && /[^A-Za-z0-9]/.test(newPassword))) {
        throw new HttpError(400, 'รหัสผ่านต้องมีตัวพิมพ์ใหญ่ ตัวพิมพ์เล็ก ตัวเลข และอักขระพิเศษ');
    }
}

app.post('/api/admin/change-password', requireAnyUser, changePasswordLimiter, asyncRoute(async (req, res) => {
    const { current_password: currentPassword, new_password: newPassword } = req.body || {};

    if (typeof currentPassword !== 'string' || typeof newPassword !== 'string' || currentPassword === '') {
        throw new HttpError(400, 'กรุณากรอกรหัสผ่านปัจจุบันและรหัสผ่านใหม่');
    }
    assertValidNewPassword(newPassword);
    if (newPassword === currentPassword) {
        throw new HttpError(400, 'รหัสผ่านใหม่ต้องไม่เหมือนรหัสผ่านปัจจุบัน');
    }

    const [[row]] = await pdb.query('SELECT password_hash FROM admin_users WHERE id = ?', [req.user.id]);
    if (!bcrypt.compareSync(currentPassword, row.password_hash)) {
        throw new HttpError(400, 'รหัสผ่านปัจจุบันไม่ถูกต้อง');
    }

    await pdb.query('UPDATE admin_users SET password_hash = ?, password_changed_at = NOW() WHERE id = ?', [await bcrypt.hash(newPassword, 10), req.user.id]);
    logActivity(req, { action: 'change_password', entity: 'admin', detail: `เปลี่ยนรหัสผ่านของ ${req.user.username}` });
    res.json({ message: 'เปลี่ยนรหัสผ่านสำเร็จ!' });
}));

// ==========================================
// 🌟 การยืนยันตัวตน 2 ขั้นตอน (2FA) ของบัญชีตัวเอง 🌟
// ==========================================
const twoFactorLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    standardHeaders: true,
    legacyHeaders: false,
    skipSuccessfulRequests: true,
    message: { error: 'ลองยืนยันผิดหลายครั้งเกินไป กรุณาลองใหม่อีกครั้งในอีก 15 นาที' },
});

async function readTwoFactorRow(userId) {
    const [[row]] = await pdb.query(
        'SELECT id, username, password_hash, totp_secret, totp_enabled, backup_codes FROM admin_users WHERE id = ?', [userId]);
    return row;
}

async function assertPasswordMatches(userId, password) {
    const row = await readTwoFactorRow(userId);
    if (typeof password !== 'string' || !bcrypt.compareSync(password, row.password_hash)) {
        throw new HttpError(400, 'รหัสผ่านไม่ถูกต้อง');
    }
    return row;
}

app.get('/api/admin/2fa/status', requireAnyUser, asyncRoute(async (req, res) => {
    const row = await readTwoFactorRow(req.user.id);
    res.json({
        enabled: Boolean(row.totp_enabled),
        backup_codes_remaining: row.totp_enabled ? parseBackupHashes(row.backup_codes).length : 0,
        backup_codes_total: BACKUP_CODE_COUNT,
        enforced: securitySettings.require_2fa,
    });
}));

// ขั้นที่ 1: สร้างความลับชั่วคราว + QR code (ยังไม่เปิดใช้จนกว่าจะยืนยันรหัสจากแอปในขั้นที่ 2)
app.post('/api/admin/2fa/setup', requireAnyUser, asyncRoute(async (req, res) => {
    const row = await readTwoFactorRow(req.user.id);
    if (row.totp_enabled) throw new HttpError(400, 'บัญชีนี้เปิดใช้งาน 2FA อยู่แล้ว');
    const secret = base32Encode(crypto.randomBytes(20));
    req.session.pending2faSetup = secret;
    const label = encodeURIComponent(`${TWO_FACTOR_ISSUER}:${req.user.username}`);
    const otpauthUrl = `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent(TWO_FACTOR_ISSUER)}&algorithm=SHA1&digits=6&period=30`;
    res.json({ secret, otpauth_url: otpauthUrl, qr: await QRCode.toDataURL(otpauthUrl, { margin: 1, width: 224 }) });
}));

// ขั้นที่ 2: ยืนยันรหัส 6 หลักจากแอป แล้วเปิดใช้งานพร้อมออกรหัสสำรอง (แสดงครั้งเดียวเท่านั้น)
app.post('/api/admin/2fa/enable', requireAnyUser, twoFactorLimiter, asyncRoute(async (req, res) => {
    const secret = req.session.pending2faSetup;
    if (!secret) throw new HttpError(400, 'กรุณากดเริ่มตั้งค่า 2FA ใหม่อีกครั้ง');
    const step = verifyTotp(secret, req.body?.code);
    if (step === null) throw new HttpError(400, 'รหัสไม่ถูกต้องหรือหมดอายุ ตรวจสอบเวลาในโทรศัพท์แล้วลองใหม่');
    const backup = await generateBackupCodes();
    await pdb.query(
        'UPDATE admin_users SET totp_secret = ?, totp_enabled = 1, totp_last_step = ?, backup_codes = ? WHERE id = ?',
        [secret, step, JSON.stringify(backup.hashes), req.user.id]);
    delete req.session.pending2faSetup;
    logActivity(req, { action: 'update', entity: 'admin', detail: `เปิดใช้งาน 2FA ของ ${req.user.username}` });
    res.json({ message: 'เปิดใช้งาน 2FA สำเร็จ!', backup_codes: backup.plain });
}));

app.post('/api/admin/2fa/disable', requireAnyUser, changePasswordLimiter, asyncRoute(async (req, res) => {
    if (securitySettings.require_2fa) throw new HttpError(400, 'ระบบบังคับใช้ 2FA กับทุกบัญชี จึงปิดการใช้งานไม่ได้');
    await assertPasswordMatches(req.user.id, req.body?.password);
    await pdb.query('UPDATE admin_users SET totp_enabled = 0, totp_secret = NULL, totp_last_step = NULL, backup_codes = NULL WHERE id = ?', [req.user.id]);
    logActivity(req, { action: 'update', entity: 'admin', detail: `ปิดใช้งาน 2FA ของ ${req.user.username}` });
    res.json({ message: 'ปิดใช้งาน 2FA แล้ว' });
}));

app.post('/api/admin/2fa/backup-codes', requireAnyUser, changePasswordLimiter, asyncRoute(async (req, res) => {
    const row = await assertPasswordMatches(req.user.id, req.body?.password);
    if (!row.totp_enabled) throw new HttpError(400, 'ต้องเปิดใช้งาน 2FA ก่อน');
    const backup = await generateBackupCodes();
    await pdb.query('UPDATE admin_users SET backup_codes = ? WHERE id = ?', [JSON.stringify(backup.hashes), req.user.id]);
    logActivity(req, { action: 'update', entity: 'admin', detail: `สร้างรหัสสำรอง 2FA ชุดใหม่ของ ${req.user.username}` });
    res.json({ message: 'สร้างรหัสสำรองชุดใหม่แล้ว (ชุดเก่าใช้ไม่ได้อีก)', backup_codes: backup.plain });
}));

// ==========================================
// 🌟 โปรไฟล์ผู้ดูแล (ชื่อ อีเมล เบอร์โทร สังกัด รูป) 🌟
// ==========================================
const PROFILE_FIELDS = {
    full_name: { label: 'ชื่อ-นามสกุล', max: 100 },
    email: { label: 'อีเมล', max: 120 },
    phone: { label: 'เบอร์โทรศัพท์', max: 40 },
    department: { label: 'สังกัด / หน่วยงาน', max: 150 },
};
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const AVATAR_SIZE = 256;

function readProfileFields(body) {
    const fields = {};
    for (const [key, rule] of Object.entries(PROFILE_FIELDS)) {
        const value = typeof body?.[key] === 'string' ? body[key].trim() : '';
        if (value.length > rule.max) throw new HttpError(400, `${rule.label}ยาวเกินไป (ไม่เกิน ${rule.max} ตัวอักษร)`);
        fields[key] = value;
    }
    if (fields.email && !EMAIL_PATTERN.test(fields.email)) throw new HttpError(400, 'รูปแบบอีเมลไม่ถูกต้อง');
    return fields;
}

const USER_COLUMNS = 'id, username, role, status, full_name, email, phone, department, avatar, last_login_at, last_login_ip, created_at, totp_enabled, password_changed_at, locked_until';

function publicUser(row) {
    return { ...row, totp_enabled: Boolean(row.totp_enabled), role_label: roleLabelTh(row.role) };
}

async function readUser(id) {
    const [rows] = await pdb.query(`SELECT ${USER_COLUMNS} FROM admin_users WHERE id = ?`, [id]);
    return rows[0] ? publicUser(rows[0]) : null;
}

app.get('/api/admin/profile', requireAuth, asyncRoute(async (req, res) => {
    res.json(await readUser(req.user.id));
}));

app.put('/api/admin/profile', requireAuth, asyncRoute(async (req, res) => {
    const fields = readProfileFields(req.body);
    await pdb.query(
        'UPDATE admin_users SET full_name = ?, email = ?, phone = ?, department = ? WHERE id = ?',
        [fields.full_name, fields.email, fields.phone, fields.department, req.user.id]);
    logActivity(req, { action: 'update', entity: 'admin', detail: `แก้ไขข้อมูลส่วนตัวของ ${req.user.username}` });
    res.json({ message: 'บันทึกข้อมูลส่วนตัวสำเร็จ!', ...(await readUser(req.user.id)) });
}));

// รูปโปรไฟล์ย่อเป็นสี่เหลี่ยมจัตุรัสแล้วเก็บเป็น data URL ในฐานข้อมูล ไม่ต้องมีโฟลเดอร์ไฟล์เพิ่ม และไปกับ backup ฐานข้อมูลอัตโนมัติ
const avatarUploader = createImageUploader(5 * 1024 * 1024);
app.post('/api/admin/profile/avatar', requireAuth, handleUpload(avatarUploader, 'image', 5), asyncRoute(async (req, res) => {
    if (!req.file) throw new HttpError(400, 'กรุณาเลือกไฟล์รูปภาพ');
    try { imageSize(req.file.buffer); } catch (err) { throw new HttpError(400, 'ไฟล์รูปไม่ถูกต้องหรือเสียหาย'); }
    const buffer = await sharp(req.file.buffer).rotate()
        .resize(AVATAR_SIZE, AVATAR_SIZE, { fit: 'cover' }).webp({ quality: 82 }).toBuffer();
    const avatar = `data:image/webp;base64,${buffer.toString('base64')}`;
    await pdb.query('UPDATE admin_users SET avatar = ? WHERE id = ?', [avatar, req.user.id]);
    logActivity(req, { action: 'update', entity: 'admin', detail: `เปลี่ยนรูปโปรไฟล์ของ ${req.user.username}` });
    res.json({ message: 'เปลี่ยนรูปโปรไฟล์สำเร็จ!', avatar });
}));

app.delete('/api/admin/profile/avatar', requireAuth, asyncRoute(async (req, res) => {
    await pdb.query('UPDATE admin_users SET avatar = NULL WHERE id = ?', [req.user.id]);
    logActivity(req, { action: 'update', entity: 'admin', detail: `ลบรูปโปรไฟล์ของ ${req.user.username}` });
    res.json({ message: 'ลบรูปโปรไฟล์แล้ว', avatar: null });
}));

// ==========================================
// 🌟 จัดการบัญชีผู้ดูแลและบทบาท (เฉพาะผู้มีสิทธิ์ settings) 🌟
// ==========================================
const requireUserAdmin = requirePerm('settings.manage');

// รายละเอียดบทบาทสำหรับหน้า Settings (รวมจำนวนบัญชีที่ใช้บทบาทนั้น และค่าตั้งต้นของบทบาทระบบไว้ใช้ปุ่มรีเซ็ต)
function roleView(role, userCount) {
    const defaults = DEFAULT_ROLE_BY_KEY.get(role.key);
    return {
        key: role.key, label: role.label, label_th: role.label_th, description: role.description,
        permissions: [...role.permissions], is_system: role.is_system, locked: role.key === SUPER_ROLE,
        user_count: userCount, default_permissions: defaults ? normalizePermissions(defaults.permissions) : null,
    };
}

app.get('/api/admin/roles', requireUserAdmin, asyncRoute(async (req, res) => {
    await ensureRolesLoaded();
    const [counts] = await pdb.query('SELECT role, COUNT(*) AS total FROM admin_users GROUP BY role');
    const countByRole = Object.fromEntries(counts.map(row => [row.role, row.total]));
    res.json({
        modules: PERMISSION_MODULES,
        roles: [...rolesCache.values()].map(role => roleView(role, countByRole[role.key] || 0)),
    });
}));

function readRoleFields(body) {
    const label = typeof body?.label === 'string' ? body.label.trim() : '';
    const labelTh = typeof body?.label_th === 'string' ? body.label_th.trim() : '';
    const description = typeof body?.description === 'string' ? body.description.trim() : '';
    if (label.length < 2 || label.length > 60) throw new HttpError(400, 'ชื่อบทบาท (ภาษาอังกฤษ) ต้องยาว 2-60 ตัวอักษร');
    if (labelTh.length > 100) throw new HttpError(400, 'ชื่อแสดงภาษาไทยยาวเกินไป (ไม่เกิน 100 ตัวอักษร)');
    if (description.length > 300) throw new HttpError(400, 'คำอธิบายยาวเกินไป (ไม่เกิน 300 ตัวอักษร)');
    return { label, labelTh, description, permissions: normalizePermissions(body?.permissions) };
}

app.post('/api/admin/roles', requireUserAdmin, asyncRoute(async (req, res) => {
    const key = typeof req.body?.key === 'string' ? req.body.key.trim().toLowerCase() : '';
    if (!ROLE_KEY_PATTERN.test(key)) {
        throw new HttpError(400, 'รหัสบทบาทต้องยาว 3-30 ตัว ขึ้นต้นด้วย a-z และใช้ได้เฉพาะ a-z 0-9 และขีดล่าง');
    }
    const fields = readRoleFields(req.body);
    try {
        await pdb.query(
            'INSERT INTO admin_roles (role_key, label, label_th, description, permissions, is_system) VALUES (?, ?, ?, ?, ?, 0)',
            [key, fields.label, fields.labelTh, fields.description, JSON.stringify(fields.permissions)]);
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') throw new HttpError(409, 'รหัสบทบาทนี้ถูกใช้แล้ว');
        throw err;
    }
    await reloadRoles();
    logActivity(req, { action: 'create', entity: 'admin', detail: `สร้างบทบาท ${fields.label} (${fields.permissions.length} สิทธิ์)` });
    res.status(201).json({ message: 'สร้างบทบาทใหม่สำเร็จ!', role: roleView(rolesCache.get(key), 0) });
}));

app.put('/api/admin/roles/:key', requireUserAdmin, asyncRoute(async (req, res) => {
    const key = req.params.key;
    const existing = rolesCache.get(key);
    if (!existing) throw new HttpError(404, 'ไม่พบบทบาทนี้');
    if (key === SUPER_ROLE) throw new HttpError(400, 'บทบาทผู้ดูแลระบบสูงสุดแก้ไขไม่ได้');
    const fields = readRoleFields(req.body);
    await pdb.query(
        'UPDATE admin_roles SET label = ?, label_th = ?, description = ?, permissions = ? WHERE role_key = ?',
        [fields.label, fields.labelTh, fields.description, JSON.stringify(fields.permissions), key]);
    await reloadRoles();
    const added = fields.permissions.filter(permission => !existing.permissions.has(permission));
    const removed = [...existing.permissions].filter(permission => !fields.permissions.includes(permission));
    logActivity(req, {
        action: 'update', entity: 'admin',
        detail: `แก้ไขสิทธิ์บทบาท ${fields.label}: เพิ่ม ${added.length} เอาออก ${removed.length} สิทธิ์${removed.length > 0 ? ` (${removed.join(', ')})` : ''}`,
    });
    const [[{ total }]] = await pdb.query('SELECT COUNT(*) AS total FROM admin_users WHERE role = ?', [key]);
    res.json({ message: 'บันทึกการเปลี่ยนแปลงสิทธิ์สำเร็จ! มีผลกับบัญชีในบทบาทนี้ทันที', role: roleView(rolesCache.get(key), total) });
}));

app.delete('/api/admin/roles/:key', requireUserAdmin, asyncRoute(async (req, res) => {
    const key = req.params.key;
    const existing = rolesCache.get(key);
    if (!existing) throw new HttpError(404, 'ไม่พบบทบาทนี้');
    if (existing.is_system) throw new HttpError(400, 'บทบาทตั้งต้นของระบบลบไม่ได้');
    const [[{ total }]] = await pdb.query('SELECT COUNT(*) AS total FROM admin_users WHERE role = ?', [key]);
    if (total > 0) throw new HttpError(409, `ยังมี ${total} บัญชีใช้บทบาทนี้อยู่ ย้ายบัญชีเหล่านั้นไปบทบาทอื่นก่อน`);
    await pdb.query('DELETE FROM admin_roles WHERE role_key = ?', [key]);
    await reloadRoles();
    logActivity(req, { action: 'delete', entity: 'admin', detail: `ลบบทบาท ${existing.label}` });
    res.json({ message: `ลบบทบาท ${existing.label} แล้ว` });
}));

app.get('/api/admin/users', requireUserAdmin, asyncRoute(async (req, res) => {
    const [rows] = await pdb.query(`SELECT ${USER_COLUMNS} FROM admin_users ORDER BY id`);
    res.json({ users: rows.map(row => ({ ...publicUser(row), is_self: row.id === req.user.id })) });
}));

function assertValidRole(role) {
    if (!rolesCache.has(role)) throw new HttpError(400, 'บทบาทไม่ถูกต้อง');
}

app.post('/api/admin/users', requireUserAdmin, asyncRoute(async (req, res) => {
    const body = req.body || {};
    const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
    if (!USERNAME_PATTERN.test(username)) {
        throw new HttpError(400, 'ชื่อผู้ใช้ต้องยาว 3-30 ตัว ใช้ได้เฉพาะ a-z 0-9 จุด ขีดกลาง และขีดล่าง');
    }
    assertValidRole(body.role);
    assertValidNewPassword(body.password);
    const fields = readProfileFields(body);

    let insertId;
    try {
        const [result] = await pdb.query(
            `INSERT INTO admin_users (username, password_hash, role, full_name, email, phone, department, password_changed_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, NOW())`,
            [username, await bcrypt.hash(body.password, 10), body.role, fields.full_name, fields.email, fields.phone, fields.department]);
        insertId = result.insertId;
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') throw new HttpError(409, 'ชื่อผู้ใช้นี้ถูกใช้แล้ว');
        throw err;
    }
    logActivity(req, { action: 'create', entity: 'admin', entityId: insertId, detail: `เพิ่มบัญชีผู้ดูแล ${username} (${roleLabelTh(body.role)})` });
    res.status(201).json({ message: 'เพิ่มผู้ดูแลระบบสำเร็จ!', user: await readUser(insertId) });
}));

app.put('/api/admin/users/:id', requireUserAdmin, asyncRoute(async (req, res) => {
    const id = Number.parseInt(req.params.id, 10);
    const target = await readUser(id);
    if (!target) throw new HttpError(404, 'ไม่พบบัญชีผู้ใช้นี้');

    const body = req.body || {};
    assertValidRole(body.role);
    if (!USER_STATUSES.includes(body.status)) throw new HttpError(400, 'สถานะบัญชีไม่ถูกต้อง');
    if (id === req.user.id && (body.role !== target.role || body.status !== target.status)) {
        throw new HttpError(400, 'ไม่สามารถเปลี่ยนบทบาทหรือระงับบัญชีของตัวเองได้');
    }
    const fields = readProfileFields(body);

    await pdb.query(
        `UPDATE admin_users SET role = ?, status = ?, full_name = ?, email = ?, phone = ?, department = ? WHERE id = ?`,
        [body.role, body.status, fields.full_name, fields.email, fields.phone, fields.department, id]);
    const changes = [];
    if (body.role !== target.role) changes.push(`บทบาท ${roleLabelTh(target.role)} → ${roleLabelTh(body.role)}`);
    if (body.status !== target.status) changes.push(body.status === 'active' ? 'เปิดใช้งานบัญชี' : 'ระงับบัญชี');
    logActivity(req, {
        action: 'update', entity: 'admin', entityId: id,
        detail: `แก้ไขบัญชี ${target.username}${changes.length > 0 ? `: ${changes.join(', ')}` : ''}`,
    });
    res.json({ message: 'บันทึกการแก้ไขบัญชีสำเร็จ!', user: await readUser(id) });
}));

app.post('/api/admin/users/:id/reset-password', requireUserAdmin, asyncRoute(async (req, res) => {
    const id = Number.parseInt(req.params.id, 10);
    const target = await readUser(id);
    if (!target) throw new HttpError(404, 'ไม่พบบัญชีผู้ใช้นี้');
    assertValidNewPassword(req.body?.new_password);
    await pdb.query('UPDATE admin_users SET password_hash = ?, password_changed_at = NOW() WHERE id = ?', [await bcrypt.hash(req.body.new_password, 10), id]);
    logActivity(req, { action: 'change_password', entity: 'admin', entityId: id, detail: `รีเซ็ตรหัสผ่านของ ${target.username}` });
    res.json({ message: `รีเซ็ตรหัสผ่านของ ${target.username} แล้ว` });
}));

app.delete('/api/admin/users/:id', requireUserAdmin, asyncRoute(async (req, res) => {
    const id = Number.parseInt(req.params.id, 10);
    const target = await readUser(id);
    if (!target) throw new HttpError(404, 'ไม่พบบัญชีผู้ใช้นี้');
    if (id === req.user.id) throw new HttpError(400, 'ไม่สามารถลบบัญชีของตัวเองได้');
    await pdb.query('DELETE FROM admin_users WHERE id = ?', [id]);
    logActivity(req, { action: 'delete', entity: 'admin', entityId: id, detail: `ลบบัญชีผู้ดูแล ${target.username}` });
    res.json({ message: `ลบบัญชี ${target.username} แล้ว` });
}));

// ==========================================
// 🌟 ตั้งค่านโยบายความปลอดภัย / ตรวจสอบความปลอดภัย (เฉพาะผู้จัดการระบบ) 🌟
// ==========================================
app.post('/api/admin/users/:id/reset-2fa', requireUserAdmin, asyncRoute(async (req, res) => {
    const id = Number.parseInt(req.params.id, 10);
    const target = await readUser(id);
    if (!target) throw new HttpError(404, 'ไม่พบบัญชีผู้ใช้นี้');
    await pdb.query('UPDATE admin_users SET totp_enabled = 0, totp_secret = NULL, totp_last_step = NULL, backup_codes = NULL WHERE id = ?', [id]);
    logActivity(req, { action: 'update', entity: 'admin', entityId: id, detail: `รีเซ็ต 2FA ของ ${target.username}` });
    res.json({ message: `รีเซ็ต 2FA ของ ${target.username} แล้ว (ผู้ใช้ตั้งค่าใหม่ได้เมื่อเข้าสู่ระบบ)` });
}));

app.get('/api/admin/security/settings', requireUserAdmin, asyncRoute(async (req, res) => {
    res.json({ settings: securitySettings, client_ip: normalizeIp(req.ip), choices: SECURITY_CHOICES });
}));

app.put('/api/admin/security/settings', requireUserAdmin, asyncRoute(async (req, res) => {
    const body = req.body || {};
    if (Array.isArray(body.ip_allowlist)) {
        for (const item of body.ip_allowlist) {
            if (parseAllowEntry(item?.cidr) === null) {
                throw new HttpError(400, `รูปแบบ IP ไม่ถูกต้อง: "${String(item?.cidr || '').slice(0, 50)}" (ใช้เช่น 158.108.0.0/16 หรือ 203.0.113.5)`);
            }
        }
    }
    const next = sanitizeSecuritySettings({ ...securitySettings, ...body }, securitySettings);
    if (next.ip_allowlist_enabled && !isIpAllowed(req.ip, next.ip_allowlist)) {
        throw new HttpError(400, `IP ปัจจุบันของคุณ (${normalizeIp(req.ip)}) ไม่อยู่ในรายการ ถ้าเปิดใช้งานจะล็อกตัวเองออกจากระบบ กรุณาเพิ่ม IP นี้ก่อน`);
    }
    if (next.ip_allowlist_enabled && next.ip_allowlist.length === 0) {
        throw new HttpError(400, 'ต้องมี IP อย่างน้อยหนึ่งรายการก่อนเปิดใช้การจำกัด IP');
    }
    await pdb.query(
        `INSERT INTO admin_settings (setting_key, setting_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`,
        [SECURITY_SETTING_KEY, JSON.stringify(next)]);
    const changed = Object.keys(next).filter(key => JSON.stringify(next[key]) !== JSON.stringify(securitySettings[key]));
    securitySettings = next;
    logActivity(req, { action: 'update', entity: 'admin', detail: `แก้ไขนโยบายความปลอดภัย${changed.length > 0 ? `: ${changed.join(', ')}` : ' (ไม่มีการเปลี่ยนแปลง)'}` });
    res.json({ message: 'บันทึกการตั้งค่าความปลอดภัยสำเร็จ!', settings: securitySettings });
}));

// นับ session ที่ยังใช้งานได้จริงของผู้ดูแล (MemoryStore เก็บในหน่วยความจำ เริ่มระบบใหม่แล้วทุกคนต้องล็อกอินใหม่)
function countActiveSessions() {
    return new Promise((resolve) => {
        sessionStore.all((err, sessions) => {
            if (err || !sessions) return resolve(0);
            resolve(Object.values(sessions).filter(item => item && item.userId).length);
        });
    });
}

app.get('/api/admin/security/audit', requireUserAdmin, asyncRoute(async (req, res) => {
    const [users] = await pdb.query('SELECT id, username, password_hash, status, totp_enabled FROM admin_users');
    const activeUsers = users.filter(user => user.status === 'active');
    const twoFactorCount = activeUsers.filter(user => user.totp_enabled).length;

    // บัญชีที่ยังใช้รหัสผ่านเริ่มต้น (ค่าตั้งต้นในระบบ/docker-compose หรือรหัสเท่ากับชื่อผู้ใช้)
    const defaultCandidates = new Set(['admin1234', 'editor1234', process.env.ADMIN_PASSWORD, process.env.EDITOR_PASSWORD].filter(Boolean));
    const weakAccounts = [];
    for (const user of activeUsers) {
        const candidates = [...defaultCandidates, user.username];
        for (const candidate of candidates) {
            if (await bcrypt.compare(candidate, user.password_hash)) { weakAccounts.push(user.username); break; }
        }
    }
    const [[failed]] = await pdb.query(
        "SELECT COUNT(*) AS total FROM activity_logs WHERE action = 'login_failed' AND created_at >= NOW() - INTERVAL 1 DAY");
    const sessions = await countActiveSessions();
    const https = req.secure;
    const s = securitySettings;
    const ratio = activeUsers.length === 0 ? 1 : twoFactorCount / activeUsers.length;
    const checks = [
        { key: 'two_factor', label: 'เปิด 2FA ครบทุกบัญชีที่ใช้งาน', weight: 25, score: ratio, ok: ratio === 1, detail: `${twoFactorCount} จาก ${activeUsers.length} บัญชี`, fix: 'ให้แต่ละบัญชีเปิด 2FA ที่แท็บ ความปลอดภัย หรือเปิด "บังคับใช้ 2FA"' },
        { key: 'default_passwords', label: 'ไม่มีบัญชีที่ใช้รหัสผ่านเริ่มต้น', weight: 25, score: weakAccounts.length === 0 ? 1 : 0, ok: weakAccounts.length === 0, detail: weakAccounts.length === 0 ? 'ไม่พบ' : `พบ: ${weakAccounts.join(', ')}`, fix: 'รีเซ็ตหรือเปลี่ยนรหัสผ่านของบัญชีเหล่านี้ทันที' },
        { key: 'enforce_2fa', label: 'บังคับใช้ 2FA กับทุกบัญชี', weight: 10, score: s.require_2fa ? 1 : 0, ok: s.require_2fa, detail: s.require_2fa ? 'เปิดอยู่' : 'ปิดอยู่', fix: 'เปิดสวิตช์บังคับใช้ 2FA' },
        { key: 'password_policy', label: 'นโยบายรหัสผ่านเข้มแข็ง (ยาว ≥ 10 และซับซ้อน)', weight: 10, score: (s.password_min_length >= 10 ? 0.5 : 0) + (s.password_complexity ? 0.5 : 0), ok: s.password_min_length >= 10 && s.password_complexity, detail: `ขั้นต่ำ ${s.password_min_length} ตัว • ความซับซ้อน ${s.password_complexity ? 'เปิด' : 'ปิด'}`, fix: 'เพิ่มความยาวขั้นต่ำเป็น 10 ขึ้นไปและเปิดความซับซ้อน' },
        { key: 'session_timeout', label: 'เซสชันหมดอายุเมื่อไม่ใช้งาน ≤ 1 ชั่วโมง', weight: 10, score: s.session_timeout_minutes <= 60 ? 1 : 0, ok: s.session_timeout_minutes <= 60, detail: `${s.session_timeout_minutes} นาที`, fix: 'ลดเวลาเซสชันเหลือ 60 นาทีหรือน้อยกว่า' },
        { key: 'lockout', label: 'ล็อกบัญชีอัตโนมัติเมื่อใส่รหัสผิด', weight: 5, score: s.account_lockout ? 1 : 0, ok: s.account_lockout, detail: s.account_lockout ? `ล็อก ${LOCKOUT_MINUTES} นาที เมื่อผิด ${LOCKOUT_MAX_ATTEMPTS} ครั้ง` : 'ปิดอยู่', fix: 'เปิดการล็อกบัญชีอัตโนมัติ' },
        { key: 'password_expiry', label: 'กำหนดอายุรหัสผ่าน', weight: 5, score: s.password_expiry_days > 0 ? 1 : 0, ok: s.password_expiry_days > 0, detail: s.password_expiry_days > 0 ? `ทุก ${s.password_expiry_days} วัน` : 'ไม่หมดอายุ', fix: 'ตั้งให้เปลี่ยนรหัสผ่านทุก 90 วัน' },
        { key: 'ip_allowlist', label: 'จำกัด IP ที่เข้าระบบจัดการได้', weight: 5, score: s.ip_allowlist_enabled ? 1 : 0, ok: s.ip_allowlist_enabled, detail: s.ip_allowlist_enabled ? `${s.ip_allowlist.length} รายการ` : 'ปิดอยู่', fix: 'เพิ่มช่วง IP ของหน่วยงานแล้วเปิดใช้งาน (ถ้ามี IP คงที่)' },
        { key: 'https', label: 'เชื่อมต่อผ่าน HTTPS', weight: 5, score: https ? 1 : 0, ok: https, detail: https ? 'ใช่' : 'ยังเป็น HTTP (ปกติบนเครื่องพัฒนา)', fix: 'ใช้ HTTPS บนโฮสต์จริง' },
    ];
    const totalWeight = checks.reduce((sum, item) => sum + item.weight, 0);
    const score = Math.round(checks.reduce((sum, item) => sum + item.weight * item.score, 0) / totalWeight * 100);
    res.json({
        score, checks,
        metrics: { users_active: activeUsers.length, two_factor_enabled: twoFactorCount, failed_logins_24h: failed.total, active_sessions: sessions, https },
    });
}));

app.get('/api/admin/security/events', requireUserAdmin, asyncRoute(async (req, res) => {
    const [rows] = await pdb.query(
        `SELECT id, action, entity, detail, username, ip, created_at FROM activity_logs
         WHERE entity IN ('session', 'admin') ORDER BY id DESC LIMIT 8`);
    res.json({ rows });
}));

// ==========================================
// 🌟 ระบบและพื้นที่จัดเก็บ (System & Storage) — เฉพาะผู้จัดการระบบ 🌟
// ==========================================
const STORAGE_DIRS = [
    { key: 'panoramas', label: 'ภาพ 360° (Panorama)', dir: PANORAMA_DIR },
    { key: 'tour-images', label: 'ภาพเดินชม 360° (Virtual Tour)', dir: TOUR_IMAGE_DIR },
    { key: 'floorplans', label: 'แผนผังชั้น (Floor Plans)', dir: FLOORPLAN_DIR },
    { key: 'covers', label: 'รูปปกอาคาร (Covers)', dir: COVER_DIR },
];

async function directoryStats(dir) {
    let files = 0; let bytes = 0;
    for (const entry of await fs.promises.readdir(dir, { withFileTypes: true })) {
        if (!entry.isFile()) continue;
        const stat = await fs.promises.stat(path.join(dir, entry.name));
        files += 1; bytes += stat.size;
    }
    return { files, bytes };
}

app.get('/api/admin/system', requireUserAdmin, asyncRoute(async (req, res) => {
    const directories = [];
    for (const item of STORAGE_DIRS) {
        let stats = { files: 0, bytes: 0 };
        let writable = true;
        try { stats = await directoryStats(item.dir); } catch (err) { writable = false; }
        try { fs.accessSync(item.dir, fs.constants.W_OK); } catch (err) { writable = false; }
        directories.push({ key: item.key, label: item.label, ...stats, writable });
    }
    let disk = null;
    try {
        const stat = await fs.promises.statfs(PUBLIC_DIR);
        disk = { total: stat.blocks * stat.bsize, free: stat.bavail * stat.bsize };
    } catch (err) { disk = null; }

    const timings = [];
    let version = null;
    let healthy = true;
    try {
        for (let i = 0; i < 3; i += 1) {
            const started = process.hrtime.bigint();
            const [[row]] = await pdb.query('SELECT VERSION() AS version');
            timings.push(Number(process.hrtime.bigint() - started) / 1e6);
            version = row.version;
        }
    } catch (err) { healthy = false; }
    let dbSize = null;
    let counts = {};
    if (healthy) {
        const [[sizeRow]] = await pdb.query(
            `SELECT COALESCE(SUM(data_length + index_length), 0) AS bytes, COUNT(*) AS tables
             FROM information_schema.tables WHERE table_schema = DATABASE()`);
        dbSize = { bytes: Number(sizeRow.bytes), tables: Number(sizeRow.tables) };
        const [[countRow]] = await pdb.query(`
            SELECT (SELECT COUNT(*) FROM buildings) AS buildings, (SELECT COUNT(*) FROM rooms) AS rooms,
                   (SELECT COUNT(*) FROM panoramas) AS panoramas, (SELECT COUNT(*) FROM floor_plans) AS floor_plans,
                   (SELECT COUNT(*) FROM tour_points) AS tour_points, (SELECT COUNT(*) FROM admin_users) AS admin_users`);
        counts = countRow;
    }
    const memory = process.memoryUsage();
    res.json({
        healthy: healthy && directories.every(item => item.writable),
        storage: { directories, total_bytes: directories.reduce((sum, item) => sum + item.bytes, 0), disk },
        database: {
            healthy, version, latency_ms: timings.length ? timings.reduce((a, b) => a + b, 0) / timings.length : null,
            size_bytes: dbSize ? dbSize.bytes : null, tables: dbSize ? dbSize.tables : null,
        },
        counts,
        server: {
            hostname: os.hostname(), node: process.version, platform: `${os.type()} ${os.arch()}`, cpus: os.cpus().length,
            uptime_seconds: Math.round(process.uptime()), memory_rss: memory.rss, memory_heap_used: memory.heapUsed,
            system_memory_total: os.totalmem(), system_memory_free: os.freemem(),
        },
        settings: systemSettings, choices: SYSTEM_CHOICES,
    });
}));

app.put('/api/admin/system/settings', requireUserAdmin, asyncRoute(async (req, res) => {
    const next = sanitizeSystemSettings({ ...systemSettings, ...(req.body || {}) }, systemSettings);
    await pdb.query(
        `INSERT INTO admin_settings (setting_key, setting_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`,
        [SYSTEM_SETTING_KEY, JSON.stringify(next)]);
    const changed = Object.keys(next).filter(key => next[key] !== systemSettings[key]);
    systemSettings = next;
    logActivity(req, { action: 'update', entity: 'admin', detail: `แก้ไขการตั้งค่าระบบ${changed.length > 0 ? `: ${changed.join(', ')}` : ' (ไม่มีการเปลี่ยนแปลง)'}` });
    res.json({ message: 'บันทึกการตั้งค่าระบบสำเร็จ!', settings: systemSettings });
}));

// ==========================================
// 🌟 สำรอง / กู้คืนข้อมูล (Backups & Disaster Recovery) — เฉพาะผู้จัดการระบบ 🌟
// ==========================================
// ไฟล์สำรองเป็น .zip รูปแบบเดียวกับสคริปต์ backup/backup.ps1 (kps_classfinder.sql + uploads/<โฟลเดอร์>/...)
// จึงกู้คืนข้ามกันได้ระหว่างสคริปต์กับหน้าเว็บ สร้างฐานข้อมูลสำรองด้วยโค้ด Node เอง ไม่ต้องมี mysqldump ในเซิร์ฟเวอร์
const BACKUP_DIR = path.join(__dirname, 'backups');
fs.mkdirSync(BACKUP_DIR, { recursive: true });
const BACKUP_NAME_PATTERN = /^kps-backup_\d{4}-\d{2}-\d{2}_\d{6}(?:_[a-z0-9-]+)?\.zip$/;
const BACKUP_SQL_ENTRY = 'kps_classfinder.sql';
const BACKUP_SETTING_KEY = 'backup_settings';
const BANGKOK_OFFSET_MS = 7 * 3600 * 1000; // เวลาประเทศไทย UTC+7 (ไม่มีเวลาออมแสง) ใช้กำหนดรอบสำรองอัตโนมัติ
const PRE_RESTORE_KEEP = 5;
const UPLOAD_ENTRY_DIRS = { floorplans: FLOORPLAN_DIR, covers: COVER_DIR, panoramas: PANORAMA_DIR, 'tour-images': TOUR_IMAGE_DIR };
const BACKUP_TYPE_LABELS = { auto: 'อัตโนมัติ', manual: 'กำหนดเอง', 'pre-restore': 'ก่อนกู้คืน', script: 'สคริปต์' };

const BACKUP_DEFAULTS = {
    enabled: false, frequency: 'daily', hour: 2, weekday: 0, // frequency: daily | 12h | weekly
    scope_plans: true, scope_panoramas: true, retention_auto: 14,
    armed_at: null, last_auto_at: null, last_run: null, last_verify: null, last_drill: null,
};
const BACKUP_CHOICES = { frequency: ['daily', '12h', 'weekly'], retention_auto: [3, 7, 14, 30, 60] };
let backupSettings = { ...BACKUP_DEFAULTS };
let backupBusy = null; // ชื่องานที่กำลังทำอยู่ (กันสำรอง/กู้คืนซ้อนกัน)

function sanitizeBackupSettings(input, base = BACKUP_DEFAULTS) {
    const source = input && typeof input === 'object' ? input : {};
    const result = { ...base };
    for (const key of ['enabled', 'scope_plans', 'scope_panoramas']) {
        if (typeof source[key] === 'boolean') result[key] = source[key];
    }
    if (BACKUP_CHOICES.frequency.includes(source.frequency)) result.frequency = source.frequency;
    if (BACKUP_CHOICES.retention_auto.includes(Number(source.retention_auto))) result.retention_auto = Number(source.retention_auto);
    const hour = Number(source.hour);
    if (Number.isInteger(hour) && hour >= 0 && hour <= 23) result.hour = hour;
    const weekday = Number(source.weekday);
    if (Number.isInteger(weekday) && weekday >= 0 && weekday <= 6) result.weekday = weekday;
    return result;
}

async function loadBackupSettings() {
    const [rows] = await pdb.query('SELECT setting_value FROM admin_settings WHERE setting_key = ?', [BACKUP_SETTING_KEY]);
    let stored = {};
    if (rows.length > 0) { try { stored = JSON.parse(rows[0].setting_value); } catch (err) { stored = {}; } }
    backupSettings = { ...sanitizeBackupSettings(stored), ...pickBackupState(stored) };
}
// ค่าสถานะที่เซิร์ฟเวอร์เขียนเอง (ไม่รับจากหน้าเว็บ)
function pickBackupState(source) {
    const state = {};
    for (const key of ['armed_at', 'last_auto_at', 'last_run', 'last_verify', 'last_drill']) state[key] = source && source[key] !== undefined ? source[key] : null;
    return state;
}
async function saveBackupSettings() {
    await pdb.query(
        `INSERT INTO admin_settings (setting_key, setting_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`,
        [BACKUP_SETTING_KEY, JSON.stringify(backupSettings)]);
}

function bangkokStamp(date = new Date()) {
    const t = new Date(date.getTime() + BANGKOK_OFFSET_MS);
    const p = n => String(n).padStart(2, '0');
    return `${t.getUTCFullYear()}-${p(t.getUTCMonth() + 1)}-${p(t.getUTCDate())}_${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

// เวลาของรอบสำรองถัดไป (หลัง fromMs) ตามเวลาไทย
function nextScheduledRun(settings, fromMs) {
    const hours = settings.frequency === '12h' ? [settings.hour % 12, (settings.hour % 12) + 12] : [settings.hour];
    const shifted = new Date(fromMs + BANGKOK_OFFSET_MS);
    let best = null;
    for (let day = 0; day <= 8; day += 1) {
        for (const hour of hours) {
            const slot = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate() + day, hour) - BANGKOK_OFFSET_MS;
            if (slot <= fromMs) continue;
            if (settings.frequency === 'weekly' && new Date(slot + BANGKOK_OFFSET_MS).getUTCDay() !== settings.weekday) continue;
            if (best === null || slot < best) best = slot;
        }
    }
    return best;
}

function backupPath(name) {
    if (!BACKUP_NAME_PATTERN.test(name)) throw new HttpError(400, 'ชื่อไฟล์สำรองไม่ถูกต้อง');
    const full = path.join(BACKUP_DIR, name);
    if (path.dirname(full) !== BACKUP_DIR) throw new HttpError(400, 'ชื่อไฟล์สำรองไม่ถูกต้อง');
    return full;
}
function readBackupMeta(name) {
    try { return JSON.parse(fs.readFileSync(`${path.join(BACKUP_DIR, name)}.json`, 'utf8')); } catch (err) { return null; }
}
function sha256File(filePath) {
    return new Promise((resolve, reject) => {
        const hash = crypto.createHash('sha256');
        fs.createReadStream(filePath).on('data', chunk => hash.update(chunk)).on('error', reject).on('end', () => resolve(hash.digest('hex')));
    });
}

async function listBackups() {
    const entries = await fs.promises.readdir(BACKUP_DIR);
    const backups = [];
    for (const name of entries.filter(item => BACKUP_NAME_PATTERN.test(item))) {
        const stat = await fs.promises.stat(path.join(BACKUP_DIR, name));
        const meta = readBackupMeta(name);
        backups.push({
            name, size: stat.size, created_at: meta?.created_at || stat.mtime.toISOString(), type: meta?.type || 'script',
            created_by: meta?.created_by || null, note: meta?.note || '', scope: meta?.scope || null,
            sha256: meta?.sha256 || null, table_counts: meta?.table_counts || null, duration_ms: meta?.duration_ms || null,
        });
    }
    return backups.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
}

async function withBackupLock(label, task) {
    if (backupBusy) throw new HttpError(409, `ระบบกำลัง${backupBusy}อยู่ กรุณารอให้เสร็จก่อน`);
    backupBusy = label;
    try { return await task(); } finally { backupBusy = null; }
}

const dumpConnection = (extra = {}) => mysql.createConnection({ ...DB_CONFIG, dateStrings: true, multipleStatements: true, charset: 'utf8mb4_unicode_ci', ...extra }).promise();

// สร้าง SQL ทั้งฐานข้อมูล (DROP + CREATE + INSERT) ภายใน snapshot เดียว ตัวเลขจำนวนแถวจึงตรงกับข้อมูลที่ dump
async function buildSqlDump() {
    const connection = await dumpConnection();
    try {
        await connection.query('SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ');
        await connection.query('START TRANSACTION WITH CONSISTENT SNAPSHOT');
        const [tableRows] = await connection.query("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'");
        const tableCounts = {};
        const parts = [
            '-- KPS ClassFinder backup (สร้างโดยแดชบอร์ด)', 'SET NAMES utf8mb4;', 'SET FOREIGN_KEY_CHECKS=0;', "SET SQL_MODE='NO_AUTO_VALUE_ON_ZERO';", '',
        ];
        for (const row of tableRows) {
            const table = Object.values(row)[0];
            const quoted = `\`${table.replaceAll('`', '``')}\``;
            const [createRows] = await connection.query(`SHOW CREATE TABLE ${quoted}`);
            parts.push(`DROP TABLE IF EXISTS ${quoted};`, `${createRows[0]['Create Table']};`);
            const [rows] = await connection.query(`SELECT * FROM ${quoted}`);
            tableCounts[table] = rows.length;
            if (rows.length > 0) {
                const columns = Object.keys(rows[0]).map(column => `\`${column.replaceAll('`', '``')}\``).join(', ');
                for (let index = 0; index < rows.length; index += 200) {
                    const values = rows.slice(index, index + 200)
                        .map(item => `(${Object.values(item).map(value => connection.escape(value)).join(', ')})`).join(',\n');
                    parts.push(`INSERT INTO ${quoted} (${columns}) VALUES\n${values};`);
                }
            }
            parts.push('');
        }
        parts.push('SET FOREIGN_KEY_CHECKS=1;');
        await connection.query('COMMIT');
        return { sql: `${parts.join('\n')}\n`, tableCounts };
    } finally {
        await connection.end();
    }
}

// สร้างไฟล์สำรอง (.zip + ไฟล์ .json บอกรายละเอียด/checksum) type: auto | manual | pre-restore
async function createBackupFile({ type, createdBy, note = '', plans = true, panoramas = true }) {
    const started = Date.now();
    const suffix = type === 'pre-restore' ? '_pre-restore' : '';
    let name = `kps-backup_${bangkokStamp()}${suffix}.zip`;
    for (let attempt = 2; fs.existsSync(path.join(BACKUP_DIR, name)); attempt += 1) {
        name = `kps-backup_${bangkokStamp()}${suffix}-${attempt}.zip`;
    }
    const finalPath = path.join(BACKUP_DIR, name);
    const partPath = `${finalPath}.part`;
    try {
        const { sql, tableCounts } = await buildSqlDump();
        const output = fs.createWriteStream(partPath);
        const archive = archiver('zip', { zlib: { level: 6 } });
        const finished = new Promise((resolve, reject) => { output.on('close', resolve); output.on('error', reject); archive.on('error', reject); });
        archive.pipe(output);
        archive.append(sql, { name: BACKUP_SQL_ENTRY });
        const scope = { database: true, plans: Boolean(plans), panoramas: Boolean(panoramas) };
        const folders = [];
        if (scope.plans) folders.push(['floorplans', FLOORPLAN_DIR], ['covers', COVER_DIR]);
        if (scope.panoramas) folders.push(['panoramas', PANORAMA_DIR], ['tour-images', TOUR_IMAGE_DIR]);
        for (const [key, dir] of folders) archive.directory(dir, `uploads/${key}`, entry => ({ ...entry, store: true })); // ไฟล์ภาพบีบอัดมาแล้ว ไม่บีบซ้ำให้เร็วขึ้น
        await archive.finalize();
        await finished;
        await fs.promises.rename(partPath, finalPath);
        const stat = await fs.promises.stat(finalPath);
        const meta = {
            version: 1, name, type, created_at: new Date().toISOString(), created_by: createdBy, note, scope,
            size: stat.size, sha256: await sha256File(finalPath), table_counts: tableCounts, duration_ms: Date.now() - started,
        };
        await fs.promises.writeFile(`${finalPath}.json`, JSON.stringify(meta, null, 2));
        return meta;
    } catch (err) {
        await fs.promises.rm(partPath, { force: true });
        throw err;
    }
}

async function deleteBackupFiles(name) {
    await fs.promises.rm(path.join(BACKUP_DIR, name), { force: true });
    await fs.promises.rm(`${path.join(BACKUP_DIR, name)}.json`, { force: true });
}

// เก็บเฉพาะชุดอัตโนมัติ/ก่อนกู้คืนล่าสุดตามที่กำหนด ชุดที่สร้างเองและชุดจากสคริปต์ไม่ถูกลบอัตโนมัติ
async function applyRetention() {
    const backups = await listBackups();
    const drop = [
        ...backups.filter(item => item.type === 'auto').slice(backupSettings.retention_auto),
        ...backups.filter(item => item.type === 'pre-restore').slice(PRE_RESTORE_KEEP),
    ];
    for (const item of drop) await deleteBackupFiles(item.name);
    return drop.length;
}

// ----- อ่านไฟล์ zip แบบสตรีม (ไม่โหลดทั้งไฟล์เข้าหน่วยความจำ) -----
function iterateZip(zipPath, handler) {
    return new Promise((resolve, reject) => {
        yauzl.open(zipPath, { lazyEntries: true, autoClose: true }, (openError, zip) => {
            if (openError) return reject(openError);
            zip.on('error', reject);
            zip.on('end', resolve);
            zip.on('entry', (entry) => {
                const open = () => new Promise((res, rej) => zip.openReadStream(entry, (err, stream) => (err ? rej(err) : res(stream))));
                Promise.resolve(handler(entry, open)).then(() => zip.readEntry(), (err) => { zip.close(); reject(err); });
            });
            zip.readEntry();
        });
    });
}
async function readZipSql(zipPath) {
    let sql = null;
    await iterateZip(zipPath, async (entry, open) => {
        if (entry.fileName !== BACKUP_SQL_ENTRY) return;
        const chunks = [];
        for await (const chunk of await open()) chunks.push(chunk);
        sql = Buffer.concat(chunks).toString('utf8');
    });
    if (sql === null) throw new HttpError(400, 'ไฟล์สำรองนี้ไม่มีข้อมูลฐานข้อมูล (kps_classfinder.sql)');
    return sql;
}
async function extractUploadsFromZip(zipPath) {
    let extracted = 0;
    await iterateZip(zipPath, async (entry, open) => {
        const parts = entry.fileName.split('/');
        const targetDir = parts.length === 3 && parts[0] === 'uploads' ? UPLOAD_ENTRY_DIRS[parts[1]] : null;
        // กัน zip-slip: รับเฉพาะ uploads/<โฟลเดอร์ที่รู้จัก>/<ชื่อไฟล์เดี่ยว>
        if (!targetDir || !parts[2] || path.basename(parts[2]) !== parts[2] || entry.fileName.endsWith('/')) return;
        const stream = await open();
        await new Promise((resolve, reject) => {
            const out = fs.createWriteStream(path.join(targetDir, parts[2]));
            stream.pipe(out); out.on('finish', resolve); out.on('error', reject); stream.on('error', reject);
        });
        extracted += 1;
    });
    return extracted;
}

// ทดสอบกู้คืนจำลอง: กู้ SQL ลงฐานข้อมูลชั่วคราวแล้วนับแถวเทียบกับตอนสำรอง จากนั้นลบทิ้ง (ไม่แตะข้อมูลจริง)
async function runRecoveryDrill(name) {
    const zipPath = backupPath(name);
    if (!fs.existsSync(zipPath)) throw new HttpError(404, 'ไม่พบไฟล์สำรองนี้');
    const meta = readBackupMeta(name);
    const sql = await readZipSql(zipPath);
    const drillDb = `kps_drill_${Date.now()}`;
    const connection = await dumpConnection({ database: undefined });
    const started = process.hrtime.bigint();
    try {
        try {
            await connection.query(`CREATE DATABASE \`${drillDb}\` CHARACTER SET utf8mb4`);
        } catch (err) {
            throw new HttpError(400, 'ผู้ใช้ฐานข้อมูลไม่มีสิทธิ์สร้างฐานข้อมูลชั่วคราว จึงทดสอบกู้คืนจำลองไม่ได้ในสภาพแวดล้อมนี้');
        }
        await connection.query(`USE \`${drillDb}\``);
        await connection.query(sql);
        const [tableRows] = await connection.query("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'");
        const counts = {};
        for (const row of tableRows) {
            const table = Object.values(row)[0];
            const [[count]] = await connection.query(`SELECT COUNT(*) AS total FROM \`${table}\``);
            counts[table] = Number(count.total);
        }
        const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
        const expected = meta?.table_counts || null;
        const mismatches = expected
            ? Object.keys({ ...expected, ...counts }).filter(table => expected[table] !== counts[table]).map(table => ({ table, expected: expected[table] ?? null, restored: counts[table] ?? null }))
            : [];
        return { backup: name, ok: Object.keys(counts).length > 0 && mismatches.length === 0, tables: Object.keys(counts).length, rows: Object.values(counts).reduce((a, b) => a + b, 0), compared: Boolean(expected), mismatches, duration_ms: Math.round(durationMs) };
    } finally {
        await connection.query(`DROP DATABASE IF EXISTS \`${drillDb}\``).catch(() => {});
        await connection.end();
    }
}

function systemLog(action, detail) {
    logActivity({ ip: '-' }, { action, entity: 'backup', detail, username: 'system' });
}

// ----- ตั้งเวลาสำรองอัตโนมัติ (ตรวจทุกนาที ถึงรอบแล้วค่อยสำรอง ถ้าเครื่องดับตอนถึงเวลาจะสำรองชดเชยตอนเปิดใหม่) -----
async function backupSchedulerTick() {
    if (!backupSettings.enabled || backupBusy) return;
    const reference = new Date(backupSettings.last_auto_at || backupSettings.armed_at || Date.now()).getTime();
    const due = nextScheduledRun(backupSettings, reference);
    if (due === null || due > Date.now()) return;
    try {
        await withBackupLock('สำรองข้อมูลอัตโนมัติ', async () => {
            const meta = await createBackupFile({ type: 'auto', createdBy: 'ระบบอัตโนมัติ', plans: backupSettings.scope_plans, panoramas: backupSettings.scope_panoramas });
            const removed = await applyRetention();
            backupSettings.last_run = { at: meta.created_at, status: 'success', type: 'auto', name: meta.name, size: meta.size };
            systemLog('create', `สำรองข้อมูลอัตโนมัติสำเร็จ (${meta.name}, ${(meta.size / 1048576).toFixed(1)} MB${removed ? `, ลบชุดเก่า ${removed} ชุด` : ''})`);
        });
    } catch (err) {
        console.error('สำรองข้อมูลอัตโนมัติไม่สำเร็จ:', err.message);
        backupSettings.last_run = { at: new Date().toISOString(), status: 'failed', type: 'auto', error: String(err.message).slice(0, 200) };
        systemLog('create', `สำรองข้อมูลอัตโนมัติไม่สำเร็จ: ${String(err.message).slice(0, 200)}`);
    }
    backupSettings.last_auto_at = new Date().toISOString();
    await saveBackupSettings().catch(() => {});
}
let backupSchedulerTimer = null;
function startBackupScheduler() {
    if (backupSchedulerTimer) return;
    backupSchedulerTimer = setInterval(() => { backupSchedulerTick().catch(err => console.error('backup scheduler:', err.message)); }, 60 * 1000);
}

function backupSettingsView() {
    const reference = new Date(backupSettings.last_auto_at || backupSettings.armed_at || Date.now()).getTime();
    const next = backupSettings.enabled ? nextScheduledRun(backupSettings, reference) : null;
    // ถ้าเลยเวลาแล้ว (เช่น เครื่องดับตอนถึงรอบ) ระบบจะสำรองชดเชยในรอบตรวจถัดไป
    return { ...backupSettings, next_run_at: next ? new Date(Math.max(next, Date.now())).toISOString() : null };
}

app.get('/api/admin/backups', requireUserAdmin, asyncRoute(async (req, res) => {
    const backups = await listBackups();
    let disk = null;
    try {
        const stat = await fs.promises.statfs(BACKUP_DIR);
        disk = { total: stat.blocks * stat.bsize, free: stat.bavail * stat.bsize };
    } catch (err) { disk = null; }
    res.json({
        backups, total_bytes: backups.reduce((sum, item) => sum + item.size, 0), disk, busy: backupBusy,
        settings: backupSettingsView(), choices: BACKUP_CHOICES, type_labels: BACKUP_TYPE_LABELS,
    });
}));

app.post('/api/admin/backups', requireUserAdmin, asyncRoute(async (req, res) => {
    const note = typeof req.body?.note === 'string' ? req.body.note.trim().slice(0, 120) : '';
    const plans = req.body?.plans !== false;
    const panoramas = req.body?.panoramas !== false;
    const meta = await withBackupLock('สำรองข้อมูล', () => createBackupFile({ type: 'manual', createdBy: req.user.username, note, plans, panoramas }));
    backupSettings.last_run = { at: meta.created_at, status: 'success', type: 'manual', name: meta.name, size: meta.size };
    await saveBackupSettings();
    logActivity(req, { action: 'create', entity: 'backup', detail: `สำรองข้อมูล ${meta.name} (${(meta.size / 1048576).toFixed(1)} MB)${labelSuffix(note)}` });
    res.status(201).json({ message: 'สำรองข้อมูลสำเร็จ!', backup: meta });
}));

app.put('/api/admin/backups/settings', requireUserAdmin, asyncRoute(async (req, res) => {
    const next = { ...sanitizeBackupSettings({ ...backupSettings, ...(req.body || {}) }, backupSettings), ...pickBackupState(backupSettings) };
    if (next.enabled && !backupSettings.enabled) next.armed_at = new Date().toISOString(); // เริ่มนับรอบจากตอนที่เปิด
    const changed = Object.keys(BACKUP_DEFAULTS).filter(key => !['armed_at', 'last_auto_at', 'last_run', 'last_verify', 'last_drill'].includes(key) && next[key] !== backupSettings[key]);
    backupSettings = next;
    await saveBackupSettings();
    logActivity(req, { action: 'update', entity: 'backup', detail: `แก้ไขกำหนดการสำรองข้อมูล${changed.length > 0 ? `: ${changed.join(', ')}` : ' (ไม่มีการเปลี่ยนแปลง)'}` });
    res.json({ message: 'บันทึกกำหนดการสำรองข้อมูลสำเร็จ!', settings: backupSettingsView() });
}));

app.get('/api/admin/backups/:name/download', requireUserAdmin, asyncRoute(async (req, res) => {
    const file = backupPath(req.params.name);
    if (!fs.existsSync(file)) throw new HttpError(404, 'ไม่พบไฟล์สำรองนี้');
    logActivity(req, { action: 'export', entity: 'backup', detail: `ดาวน์โหลดไฟล์สำรอง ${req.params.name}` });
    res.download(file, req.params.name);
}));

app.delete('/api/admin/backups/:name', requireUserAdmin, asyncRoute(async (req, res) => {
    const file = backupPath(req.params.name);
    if (!fs.existsSync(file)) throw new HttpError(404, 'ไม่พบไฟล์สำรองนี้');
    await withBackupLock('ลบไฟล์สำรอง', () => deleteBackupFiles(req.params.name));
    logActivity(req, { action: 'delete', entity: 'backup', detail: `ลบไฟล์สำรอง ${req.params.name}` });
    res.json({ message: 'ลบไฟล์สำรองแล้ว' });
}));

// ตรวจความสมบูรณ์: คำนวณ SHA-256 ของไฟล์เทียบกับค่าที่บันทึกตอนสำรอง (ไฟล์จากสคริปต์ไม่มีค่านี้ จะตรวจได้แค่ว่าเปิด zip ได้)
async function verifyBackup(name) {
    const file = backupPath(name);
    if (!fs.existsSync(file)) return { name, ok: false, reason: 'ไม่พบไฟล์' };
    const meta = readBackupMeta(name);
    try {
        let entries = 0;
        await iterateZip(file, async () => { entries += 1; });
        if (!meta?.sha256) return { name, ok: true, checksum: false, entries };
        const actual = await sha256File(file);
        return actual === meta.sha256 ? { name, ok: true, checksum: true, entries } : { name, ok: false, checksum: true, reason: 'ค่า SHA-256 ไม่ตรงกับตอนสำรอง ไฟล์อาจเสียหาย' };
    } catch (err) {
        return { name, ok: false, reason: 'เปิดไฟล์ zip ไม่ได้ ไฟล์อาจเสียหาย' };
    }
}

app.post('/api/admin/backups/verify-all', requireUserAdmin, asyncRoute(async (req, res) => {
    const results = await withBackupLock('ตรวจสอบไฟล์สำรอง', async () => {
        const out = [];
        for (const item of await listBackups()) out.push(await verifyBackup(item.name));
        return out;
    });
    backupSettings.last_verify = { at: new Date().toISOString(), total: results.length, ok: results.filter(item => item.ok).length, failed: results.filter(item => !item.ok).map(item => item.name) };
    await saveBackupSettings();
    logActivity(req, { action: 'update', entity: 'backup', detail: `ตรวจสอบความสมบูรณ์ไฟล์สำรอง ${backupSettings.last_verify.ok}/${results.length} ผ่าน` });
    res.json({ results, last_verify: backupSettings.last_verify });
}));

app.post('/api/admin/backups/drill', requireUserAdmin, asyncRoute(async (req, res) => {
    const backups = await listBackups();
    const name = typeof req.body?.name === 'string' && req.body.name ? req.body.name : backups[0]?.name;
    if (!name) throw new HttpError(400, 'ยังไม่มีไฟล์สำรองให้ทดสอบ');
    const result = await withBackupLock('ทดสอบกู้คืนจำลอง', () => runRecoveryDrill(name));
    backupSettings.last_drill = { at: new Date().toISOString(), ...result };
    await saveBackupSettings();
    logActivity(req, { action: 'update', entity: 'backup', detail: `ทดสอบกู้คืนจำลองจาก ${name}: ${result.ok ? 'ผ่าน' : 'ไม่ผ่าน'} (${result.duration_ms} ms)` });
    res.json({ message: result.ok ? 'ทดสอบกู้คืนจำลองผ่าน' : 'ทดสอบกู้คืนจำลองไม่ผ่าน', result });
}));

app.post('/api/admin/backups/:name/verify', requireUserAdmin, asyncRoute(async (req, res) => {
    res.json({ result: await withBackupLock('ตรวจสอบไฟล์สำรอง', () => verifyBackup(req.params.name)) });
}));

// กู้คืนจริง: เขียนทับฐานข้อมูลและไฟล์อัปโหลดปัจจุบัน ต้องยืนยันรหัสผ่านและพิมพ์ชื่อไฟล์ และระบบสำรองสภาพปัจจุบันไว้ให้ก่อนเสมอ
app.post('/api/admin/backups/:name/restore', requireUserAdmin, changePasswordLimiter, asyncRoute(async (req, res) => {
    const name = req.params.name;
    const file = backupPath(name);
    if (!fs.existsSync(file)) throw new HttpError(404, 'ไม่พบไฟล์สำรองนี้');
    if (req.body?.confirm !== name) throw new HttpError(400, 'พิมพ์ชื่อไฟล์สำรองให้ตรงเพื่อยืนยันการกู้คืน');
    const [[row]] = await pdb.query('SELECT password_hash FROM admin_users WHERE id = ?', [req.user.id]);
    if (typeof req.body?.password !== 'string' || !bcrypt.compareSync(req.body.password, row.password_hash)) {
        throw new HttpError(400, 'รหัสผ่านไม่ถูกต้อง');
    }
    const actor = req.user.username;
    logActivity(req, { action: 'update', entity: 'backup', detail: `เริ่มกู้คืนข้อมูลจาก ${name}` }); // เขียนก่อน เพราะตาราง log จะถูกแทนที่ด้วยข้อมูลในไฟล์สำรอง
    const outcome = await withBackupLock('กู้คืนข้อมูล', async () => {
        const sql = await readZipSql(file); // ตรวจว่าไฟล์อ่านได้ก่อนแตะข้อมูลจริง
        const safety = await createBackupFile({ type: 'pre-restore', createdBy: actor, note: `สำรองอัตโนมัติก่อนกู้คืนจาก ${name}` });
        const connection = await dumpConnection();
        try { await connection.query(sql); } finally { await connection.end(); }
        const files = await extractUploadsFromZip(file);
        await ensureDashboardSchema(); // เติมตาราง/คอลัมน์ที่ไฟล์สำรองรุ่นเก่าอาจไม่มี และโหลดบทบาท/นโยบายใหม่
        await loadBackupSettings();
        await applyRetention();
        return { safety: safety.name, files };
    });
    logActivity({ ip: clientIp(req) }, { action: 'update', entity: 'backup', username: actor, detail: `กู้คืนข้อมูลจาก ${name} สำเร็จ (ไฟล์ภาพ ${outcome.files} ไฟล์, สำรองก่อนกู้คืนไว้ที่ ${outcome.safety})` });
    res.json({ message: 'กู้คืนข้อมูลสำเร็จ! กรุณาเข้าสู่ระบบใหม่', safety_backup: outcome.safety, files: outcome.files });
}));

// ==========================================
// 🌟 ไฟล์ที่อัปโหลด (แผนผังชั้น / ภาพพาโนรามา) 🌟
// ==========================================
const IMAGE_MIME_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp']);
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
            if (!IMAGE_MIME_TYPES.has(file.mimetype)) return cb(new Error(IMAGE_TYPE_ERROR));
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
    if (rule === PANORAMA_RULE) {
        const processed = await processPanoramaImage(file.buffer, info, ext);
        const processedName = `${rule.filePrefix}${crypto.randomBytes(8).toString('hex')}${processed.ext}`;
        await fs.promises.writeFile(path.join(rule.dir, processedName), processed.buffer);
        return { url: `${rule.urlPrefix}${processedName}`, width: processed.width, height: processed.height };
    }
    const fileName = `${rule.filePrefix}${crypto.randomBytes(8).toString('hex')}${ext}`;
    await fs.promises.writeFile(path.join(rule.dir, fileName), file.buffer);
    return { url: `${rule.urlPrefix}${fileName}`, width: info.width, height: info.height };
}

// ภาพ 360° ที่อัปโหลดใหม่: ย่อถ้ากว้างเกินขีดจำกัด และ/หรือแปลงเป็น WebP ตามการตั้งค่าระบบ (ไม่แตะไฟล์เดิมที่อัปโหลดไปแล้ว)
async function processPanoramaImage(buffer, info, ext) {
    const { convert_webp: convertWebp, max_width: maxWidth, quality } = systemSettings;
    const needsResize = info.width > maxWidth;
    if (!convertWebp && !needsResize) return { buffer, ext, width: info.width, height: info.height };
    let pipeline = sharp(buffer, { limitInputPixels: 20000 * 10000 });
    if (needsResize) pipeline = pipeline.resize({ width: maxWidth, withoutEnlargement: true });
    let outExt = ext;
    if (convertWebp) {
        pipeline = pipeline.webp({ quality });
        outExt = '.webp';
    } else if (ext === '.jpg') {
        pipeline = pipeline.jpeg({ quality, mozjpeg: true });
    } else if (ext === '.png') {
        pipeline = pipeline.png({ compressionLevel: 9 });
    } else {
        pipeline = pipeline.webp({ quality });
    }
    try {
        const { data, info: out } = await pipeline.toBuffer({ resolveWithObject: true });
        return { buffer: data, ext: outExt, width: out.width, height: out.height };
    } catch (err) {
        throw new HttpError(400, 'ประมวลผลภาพไม่สำเร็จ ไฟล์อาจเสียหายหรือใหญ่เกินไป');
    }
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
const ROOM_STATUSES = new Set(['active', 'maintenance']);

// ตรวจสอบว่าข้อมูลห้องที่ส่งมาครบและถูกต้องหรือไม่ คืนข้อความ error ถ้าไม่ผ่าน หรือ null ถ้าผ่าน
// ตรวจทีละส่วนแยกจากกัน (ลดความซับซ้อนของ validateRoomInput ด้านล่าง ซึ่งแค่เรียงลำดับเรียกทั้งหมด)
function validateRoomCode(roomCode) {
    if (typeof roomCode !== 'string' || roomCode.trim() === '') return 'กรุณากรอกรหัส/ชื่อห้อง';
    if (roomCode.trim().length > ROOM_CODE_MAX_LENGTH) return `รหัส/ชื่อห้องต้องไม่เกิน ${ROOM_CODE_MAX_LENGTH} ตัวอักษร`;
    return null;
}

function validateFloorValue(floor) {
    if (typeof floor !== 'string' || floor.trim() === '') return 'กรุณาระบุชั้น';
    if (floor.trim().length > FLOOR_MAX_LENGTH) return `ข้อมูลชั้นต้องไม่เกิน ${FLOOR_MAX_LENGTH} ตัวอักษร`;
    return null;
}

function validatePinCoordinates(pinX, pinY) {
    for (const [label, value] of [['pin_x', pinX], ['pin_y', pinY]]) {
        if (value === null || value === undefined) continue;
        const num = Number(value);
        if (!Number.isFinite(num) || num < 0 || num > 100) return `ค่าพิกัด ${label} ต้องเป็นตัวเลข 0-100`;
    }
    return null;
}

function validateRoomTypeAndCapacity(roomType, capacity) {
    if (roomType !== null && roomType !== undefined && roomType !== ''
        && (typeof roomType !== 'string' || roomType.length > ROOM_TYPE_MAX_LENGTH)) {
        return `ประเภทห้องต้องไม่เกิน ${ROOM_TYPE_MAX_LENGTH} ตัวอักษร`;
    }
    if (capacity !== null && capacity !== undefined && capacity !== '') {
        const num = Number(capacity);
        if (!Number.isInteger(num) || num < 0) return 'ความจุห้องต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป';
    }
    return null;
}

function validateRoomInput({ room_code, building_name, floor, pin_x, pin_y, room_type, capacity, status, amenities }) {
    if (typeof building_name !== 'string' || building_name.trim() === '') return 'กรุณาระบุอาคาร';
    if (status !== null && status !== undefined && status !== '' && !ROOM_STATUSES.has(status)) return 'สถานะห้องไม่ถูกต้อง';
    if (amenities !== null && amenities !== undefined && typeof amenities !== 'object') return 'ข้อมูลสิ่งอำนวยความสะดวกไม่ถูกต้อง';
    return validateRoomCode(room_code)
        || validateFloorValue(floor)
        || validatePinCoordinates(pin_x, pin_y)
        || validateRoomTypeAndCapacity(room_type, capacity);
}

// หา building_id จากชื่ออาคาร คืน null ถ้าไม่พบ
function findBuildingIdByName(buildingName, callback) {
    db.query('SELECT id FROM buildings WHERE name = ?', [buildingName], (err, results) => {
        if (err) return callback(err);
        callback(null, results.length > 0 ? results[0].id : null);
    });
}

// ตรวจสอบว่ามีห้องรหัสเดียวกันในอาคารเดียวกันอยู่แล้วหรือไม่ (excludeId ใช้ตอนแก้ไขเพื่อไม่ชนกับตัวเอง)
// ชื่อ/รหัสห้องต้องไม่ซ้ำกัน แต่เฉพาะภายในชั้นเดียวกัน (ชื่อซ้ำกันคนละชั้นได้ เช่น "ลิฟต์"/"ห้องน้ำ" ที่มีทุกชั้น)
function findDuplicateRoom(roomCode, buildingId, floor, excludeId, callback) {
    let sql = 'SELECT id FROM rooms WHERE room_code = ? AND building_id = ? AND floor = ?';
    const params = [roomCode, buildingId, floor];

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
app.post('/api/rooms', requirePerm('buildings.create'), (req, res) => {
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

        findDuplicateRoom(trimmedCode, buildingId, trimmedFloor, null, (err, isDuplicate) => {
            if (err) return res.status(500).json({ error: err.message });
            if (isDuplicate) {
                return res.status(409).json({ error: 'มีห้องนี้ในชั้นเดียวกันของอาคารนี้อยู่แล้ว' });
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
app.put('/api/rooms/:id', requirePerm('buildings.create'), (req, res) => {
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

        findDuplicateRoom(trimmedCode, buildingId, trimmedFloor, roomId, (err, isDuplicate) => {
            if (err) return res.status(500).json({ error: err.message });
            if (isDuplicate) {
                return res.status(409).json({ error: 'มีห้องนี้ในชั้นเดียวกันของอาคารนี้อยู่แล้ว' });
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
app.delete('/api/rooms/:id', requirePerm('buildings.delete'), asyncRoute(async (req, res) => {
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

app.post('/api/rooms/bulk-delete', requirePerm('buildings.delete'), asyncRoute(async (req, res) => {
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
               SUM(CASE WHEN rooms.status = 'maintenance' THEN 1 ELSE 0 END) AS maintenance_count,
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

app.post('/api/buildings', requirePerm('buildings.create'), (req, res) => {
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

app.put('/api/buildings/:id', requirePerm('buildings.create'), (req, res) => {
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

app.delete('/api/buildings/:id', requirePerm('buildings.delete'), asyncRoute(async (req, res) => {
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
app.post('/api/admin/buildings/:id/cover', requirePerm('buildings.create', 'floorplans.write', 'panoramas.upload'), handleUpload(coverUploader, 'image', 10), asyncRoute(async (req, res) => {
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

app.delete('/api/admin/buildings/:id/cover', requirePerm('buildings.create', 'floorplans.write', 'panoramas.upload'), asyncRoute(async (req, res) => {
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

app.get('/api/admin/floorplans', requirePerm('floorplans.read'), asyncRoute(async (req, res) => {
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

app.post('/api/admin/floorplans', requirePerm('floorplans.write'), handleUpload(floorPlanUploader, 'image', 10), asyncRoute(async (req, res) => {
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

app.put('/api/admin/floorplans/:id', requirePerm('floorplans.write'), handleUpload(floorPlanUploader, 'image', 10), asyncRoute(async (req, res) => {
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

app.delete('/api/admin/floorplans/:id', requirePerm('floorplans.delete'), asyncRoute(async (req, res) => {
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

const ICON_TYPES = new Set(['arrow', 'door', 'stairs', 'info']);
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
    if (icon_type !== undefined && icon_type !== null && icon_type !== '' && !ICON_TYPES.has(icon_type)) {
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

app.post('/api/rooms/:roomId/panoramas', requirePerm('panoramas.upload'), handleUpload(panoramaUploader, 'image', 20), asyncRoute(async (req, res) => {
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
        detail: `อัปโหลดภาพ 360° ห้อง "${rooms[0].room_code}"${labelSuffix(positionLabel)}`,
    });
    res.json({ message: 'อัปโหลดภาพพาโนรามาสำเร็จ!', id: insertId, image_url: saved.url });
}));

// แก้ไขป้ายชื่อ/ลำดับของภาพ (ถ้าจะเปลี่ยนไฟล์รูปให้ลบแล้วอัปโหลดใหม่)
app.put('/api/panoramas/:id', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
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

app.delete('/api/panoramas/:id', requirePerm('panoramas.delete'), asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสภาพไม่ถูกต้อง');

    const [rows] = await pdb.query('SELECT image_url FROM panoramas WHERE id = ?', [id]);
    if (rows.length === 0) throw new HttpError(404, 'ไม่พบภาพพาโนรามานี้');

    await pdb.query('DELETE FROM panoramas WHERE id = ?', [id]);
    removeUploadedFiles([rows[0].image_url]);

    logActivity(req, { action: 'delete', entity: 'panorama', entityId: id, detail: `ลบภาพ 360° #${id}` });
    res.json({ message: 'ลบภาพพาโนรามาสำเร็จ!' });
}));

app.post('/api/panoramas/:panoramaId/hotspots', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
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
        detail: `เพิ่มจุดเชื่อมในภาพ 360° #${panoramaId}${labelSuffix(label)}`,
    });
    res.json({ message: 'เพิ่มจุดเชื่อมสำเร็จ!', id: result.insertId });
}));

app.put('/api/hotspots/:id', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
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

app.delete('/api/hotspots/:id', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
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
app.get('/api/admin/tour/points', requirePerm('panoramas.read'), asyncRoute(async (req, res) => {
    const buildingId = parsePositiveInt(req.query.building_id);
    if (buildingId === null) throw new HttpError(400, 'กรุณาเลือกอาคาร');

    const [points] = await pdb.query(`${TOUR_POINT_SELECT} WHERE tp.building_id = ? ORDER BY tp.id`, [buildingId]);
    const ids = points.map(point => point.id);
    const [links] = ids.length === 0 ? [[]] : await pdb.query(
        'SELECT point_a, point_b FROM tour_links WHERE point_a IN (?) ORDER BY id', [ids]);
    res.json({ points: points.map(formatTourPoint), links: links.map(link => [link.point_a, link.point_b]) });
}));

app.post('/api/admin/tour/points', requirePerm('panoramas.upload'), handleUpload(tourImageUploader, 'image', 40), asyncRoute(async (req, res) => {
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
        detail: `อัปโหลดจุดเดินชม ${buildings[0].name} ชั้น ${floor}${labelSuffix(label)}`,
    });
    const [rows] = await pdb.query(`${TOUR_POINT_SELECT} WHERE tp.id = ?`, [insertId]);
    res.json({ message: 'อัปโหลดภาพเดินชมสำเร็จ!', point: formatTourPoint(rows[0]) });
}));

// แก้ไขเฉพาะฟิลด์ที่ส่งมา: x, y (วาง/ย้ายบนแผนผัง), heading, label, room_id, floor
// แก้ไขจุดเดินชมเฉพาะฟิลด์ที่ส่งมา — แยกแต่ละฟิลด์เป็นฟังก์ชันของตัวเอง (ลดความซับซ้อนของ route ด้านล่าง)
function applyPointPositionUpdate(body, updates) {
    if (!('x' in body || 'y' in body)) return;
    const x = parsePercent(body.x ?? null, 'ตำแหน่ง x');
    const y = parsePercent(body.y ?? null, 'ตำแหน่ง y');
    if ((x === null) !== (y === null)) throw new HttpError(400, 'ต้องระบุตำแหน่ง x และ y คู่กัน');
    updates.x = x;
    updates.y = y;
}

function applyPointLabelUpdate(body, updates) {
    if (!('label' in body)) return;
    const label = typeof body.label === 'string' ? body.label.trim() : '';
    if (label.length > TOUR_LABEL_MAX_LENGTH) throw new HttpError(400, `ชื่อจุดต้องไม่เกิน ${TOUR_LABEL_MAX_LENGTH} ตัวอักษร`);
    updates.label = label || null;
}

function applyPointFloorUpdate(body, updates) {
    if (!('floor' in body)) return;
    const floor = typeof body.floor === 'string' ? body.floor.trim() : '';
    if (!floor || floor.length > FLOOR_MAX_LENGTH) throw new HttpError(400, 'กรุณาระบุชั้น');
    updates.floor = floor;
}

async function applyPointRoomIdUpdate(body, updates, buildingId) {
    if (!('room_id' in body)) return;
    if (body.room_id === null || body.room_id === '') {
        updates.room_id = null;
        return;
    }
    const roomId = parsePositiveInt(body.room_id);
    const [rooms] = roomId === null ? [[]] : await pdb.query(
        'SELECT id FROM rooms WHERE id = ? AND building_id = ?', [roomId, buildingId]);
    if (rooms.length === 0) throw new HttpError(400, 'ห้องที่เลือกต้องอยู่ในอาคารเดียวกัน');
    updates.room_id = roomId;
}

app.put('/api/admin/tour/points/:id', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
    const id = parsePositiveInt(req.params.id);
    if (id === null) throw new HttpError(400, 'รหัสจุดไม่ถูกต้อง');
    const [existing] = await pdb.query('SELECT building_id FROM tour_points WHERE id = ?', [id]);
    if (existing.length === 0) throw new HttpError(404, 'ไม่พบจุดเดินชมนี้');

    const body = req.body || {};
    const updates = {};
    applyPointPositionUpdate(body, updates);
    if ('heading' in body) updates.heading = normalizeHeading(body.heading);
    applyPointLabelUpdate(body, updates);
    applyPointFloorUpdate(body, updates);
    await applyPointRoomIdUpdate(body, updates, existing[0].building_id);
    if (Object.keys(updates).length === 0) throw new HttpError(400, 'ไม่มีข้อมูลที่จะแก้ไข');

    await pdb.query('UPDATE tour_points SET ? WHERE id = ?', [updates, id]);
    logActivity(req, { action: 'update', entity: 'tour_point', entityId: id, detail: `แก้ไขจุดเดินชม #${id}` });
    const [rows] = await pdb.query(`${TOUR_POINT_SELECT} WHERE tp.id = ?`, [id]);
    res.json({ message: 'บันทึกจุดเดินชมสำเร็จ!', point: formatTourPoint(rows[0]) });
}));

app.delete('/api/admin/tour/points/:id', requirePerm('panoramas.delete'), asyncRoute(async (req, res) => {
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

app.post('/api/admin/tour/links', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
    const [a, b] = await parseTourLink(req.body);
    await pdb.query('INSERT IGNORE INTO tour_links (point_a, point_b) VALUES (?, ?)', [a, b]);
    logActivity(req, { action: 'create', entity: 'tour_link', detail: `เชื่อมจุดเดินชม #${a} ↔ #${b}` });
    res.json({ message: 'เชื่อมจุดสำเร็จ!' });
}));

app.delete('/api/admin/tour/links', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
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

// จุดอื่นทั้งหมด เรียงจากใกล้ไปไกล พร้อมทิศ (องศา) จาก point ไปยังแต่ละจุด
function nearbyPoints(point, points) {
    return points
        .filter(other => other !== point)
        .map(other => ({
            other,
            distance: Math.hypot(other.px - point.px, other.py - point.py),
            angle: Math.atan2(other.px - point.px, point.py - other.py) * 180 / Math.PI,
        }))
        .sort((p, q) => p.distance - q.distance);
}

// เลือกจุดใกล้สุดในแต่ละทิศ (ไม่เกิน AUTOLINK_MAX_PER_POINT จุด ไม่ไกลกว่าจุดใกล้สุดเกิน AUTOLINK_DISTANCE_FACTOR เท่า
// และไม่เลือกจุดที่อยู่ทิศเดียวกันซ้ำ กันเส้นทับกันตอนจุดเรียงเป็นแถวตรง)
function pickLinkCandidates(others) {
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
    return chosen;
}

function autoLinkPairs(points) {
    const pairs = new Set();
    for (const point of points) {
        const others = nearbyPoints(point, points);
        if (others.length === 0) continue;
        for (const { other } of pickLinkCandidates(others)) {
            pairs.add(`${Math.min(point.id, other.id)}-${Math.max(point.id, other.id)}`);
        }
    }
    return [...pairs].map(key => key.split('-').map(Number));
}

app.post('/api/admin/tour/autolink', requirePerm('panoramas.hotspots'), asyncRoute(async (req, res) => {
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
    return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

app.get('/api/admin/rooms/export.csv', requirePerm('buildings.csv'), asyncRoute(async (req, res) => {
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

    const stamp = new Date().toISOString().slice(0, 10).replaceAll('-', '');
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

// หา column ที่บอกอาคาร (ยอมรับทั้ง building_code และ building) ต้องมี room_code กับ floor ด้วยเสมอ
function validateImportHeader(headerCols) {
    let buildingColumn = null;
    if (headerCols.includes('building_code')) buildingColumn = 'building_code';
    else if (headerCols.includes('building')) buildingColumn = 'building';
    if (buildingColumn === null || !headerCols.includes('room_code') || !headerCols.includes('floor')) {
        throw new HttpError(400, 'ไฟล์ CSV ต้องมีคอลัมน์ building_code, room_code และ floor');
    }
    return buildingColumn;
}

// ค้นอาคารได้ทั้งจากรหัสหรือชื่อเต็ม (ไม่สนตัวพิมพ์เล็ก/ใหญ่)
function buildBuildingIndex(buildings) {
    const buildingByKey = new Map();
    for (const building of buildings) {
        buildingByKey.set(building.code.toLowerCase(), building);
        if (!buildingByKey.has(building.name.toLowerCase())) buildingByKey.set(building.name.toLowerCase(), building);
    }
    return buildingByKey;
}

const blankToNull = (value) => (value === undefined || value === '' ? null : value);

// สิ่งอำนวยความสะดวก: ที่นั่ง/ปลั๊ก/แอร์ต้องเป็นจำนวนเต็ม ≥ 0, wifi เป็นข้อความไม่เกินความยาวที่กำหนด
function parseImportAmenities(record, has, errors) {
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
    return Object.keys(amenities).length > 0 ? amenities : null;
}

// อ่านเฉพาะคอลัมน์ที่มีในไฟล์ (คอลัมน์ที่ไม่ได้ส่งมาจะไม่ถูกแตะตอนอัปเดต)
function parseImportFields(record, has, errors) {
    const fields = {};
    if (has('room_type')) fields.room_type = blankToNull(record.room_type);
    if (has('capacity')) fields.capacity = blankToNull(record.capacity) === null ? null : Number(record.capacity);
    if (has('status')) fields.status = blankToNull(record.status) || 'active';
    if (has('pin_x')) fields.pin_x = blankToNull(record.pin_x) === null ? null : Number(record.pin_x);
    if (has('pin_y')) fields.pin_y = blankToNull(record.pin_y) === null ? null : Number(record.pin_y);
    if (AMENITY_COLUMNS.some((column) => has(column))) fields.amenities = parseImportAmenities(record, has, errors);
    return fields;
}

// ตรวจและแปลงข้อมูล 1 แถวของ CSV เป็นแผนงาน (สร้างใหม่/อัปเดต) โดยยังไม่แตะฐานข้อมูล
function buildImportItem(record, rowNumber, { buildingColumn, has, buildingByKey, existingByKey, seenKeys }) {
    const errors = [];
    const item = { row: rowNumber, room_code: record.room_code || '', building: record[buildingColumn] || '', errors, action: null };

    const building = buildingByKey.get(String(record[buildingColumn] || '').toLowerCase());
    if (!building) errors.push(`ไม่พบอาคาร "${record[buildingColumn] || ''}"`);

    const fields = parseImportFields(record, has, errors);
    const validationError = validateRoomInput({
        room_code: record.room_code, building_name: building ? building.name : 'x', floor: record.floor,
        pin_x: fields.pin_x, pin_y: fields.pin_y, room_type: fields.room_type,
        capacity: fields.capacity, status: fields.status, amenities: fields.amenities,
    });
    if (validationError) errors.push(validationError);
    if (!building || validationError) return item;

    const key = `${building.id}|${record.floor.trim()}|${record.room_code.trim().toLowerCase()}`;
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
    return item;
}

// ตรวจและแปลงข้อมูลทั้งไฟล์เป็นแผนงาน (สร้างใหม่/อัปเดต) โดยยังไม่แตะฐานข้อมูล
async function planRoomImport(text) {
    const { headerCols, records } = parseImportCsv(text);
    const buildingColumn = validateImportHeader(headerCols);
    if (records.length === 0) throw new HttpError(400, 'ไฟล์ CSV ไม่มีข้อมูลห้องเรียน');
    if (records.length > CSV_IMPORT_MAX_ROWS) {
        throw new HttpError(400, `นำเข้าได้ครั้งละไม่เกิน ${CSV_IMPORT_MAX_ROWS} แถว`);
    }

    const has = (column) => headerCols.includes(column);
    const [buildings] = await pdb.query('SELECT id, code, name FROM buildings');
    const buildingByKey = buildBuildingIndex(buildings);
    const [existingRooms] = await pdb.query('SELECT id, building_id, floor, room_code FROM rooms');
    const existingByKey = new Map(existingRooms.map(room => [`${room.building_id}|${room.floor}|${room.room_code.toLowerCase()}`, room.id]));
    const seenKeys = new Map();

    const context = { buildingColumn, has, buildingByKey, existingByKey, seenKeys };
    const items = records.map((record, index) => buildImportItem(record, index + 2, context)); // แถวที่ 1 คือหัวตาราง
    return { items };
}

async function insertImportRow(conn, item) {
    const f = item.fields;
    await conn.query(
        `INSERT INTO rooms (room_code, building_id, floor, room_type, capacity, status, amenities, pin_x, pin_y)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [item.room_code, item.building_id, item.floor, f.room_type ?? null, f.capacity ?? null,
            f.status || 'active', f.amenities ? JSON.stringify(f.amenities) : null, f.pin_x ?? null, f.pin_y ?? null]);
}

// แก้เฉพาะคอลัมน์ที่มีในไฟล์ CSV (คอลัมน์ที่ไม่ได้ส่งมาจะไม่ถูกแตะ)
async function updateImportRow(conn, item) {
    const f = item.fields;
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

// นำเข้าแบบทั้งหมดหรือไม่เลย (transaction) ถ้าแถวใดล้มเหลวจะย้อนกลับทั้งหมด
async function commitImportRows(items) {
    const conn = await pdb.getConnection();
    try {
        await conn.beginTransaction();
        for (const item of items) {
            await (item.action === 'create' ? insertImportRow(conn, item) : updateImportRow(conn, item));
        }
        await conn.commit();
    } catch (err) {
        await conn.rollback();
        throw err;
    } finally {
        conn.release();
    }
}

function summarizeImport(items) {
    const errorCount = items.filter(item => item.errors.length > 0).length;
    const summary = {
        total: items.length,
        create: items.filter(item => item.errors.length === 0 && item.action === 'create').length,
        update: items.filter(item => item.errors.length === 0 && item.action === 'update').length,
        errors: errorCount,
    };
    return { errorCount, summary };
}

app.post('/api/admin/rooms/import', requirePerm('buildings.csv'), asyncRoute(async (req, res) => {
    const { csv, dry_run: dryRun } = req.body || {};
    if (typeof csv !== 'string' || csv.trim() === '') {
        throw new HttpError(400, 'กรุณาเลือกไฟล์ CSV');
    }

    const { items } = await planRoomImport(csv);
    const { errorCount, summary } = summarizeImport(items);
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

    await commitImportRows(items);

    logActivity(req, {
        action: 'import', entity: 'room',
        detail: `นำเข้า CSV: เพิ่ม ${summary.create} ห้อง, อัปเดต ${summary.update} ห้อง (จาก ${summary.total} แถว)`,
    });
    res.json({ message: `นำเข้าสำเร็จ: เพิ่ม ${summary.create} ห้อง, อัปเดต ${summary.update} ห้อง`, dry_run: false, can_import: true, summary });
}));

// ==========================================
// 🌟 System Logs และสรุปภาพรวม (Overview) 🌟
// ==========================================

// เงื่อนไขกรอง log ที่ใช้ร่วมกันทั้งรายการ ส่งออก CSV และสรุป (editor เห็นเฉพาะกิจกรรมของตัวเอง ไม่เห็นของคนอื่น)
const LOG_RANGES = { today: 'created_at >= CURDATE()', 7: 'created_at >= NOW() - INTERVAL 7 DAY', 30: 'created_at >= NOW() - INTERVAL 30 DAY' };

function buildLogFilter(req, { withUserFilters = true } = {}) {
    const where = [];
    const params = [];
    if (!hasPermission(req.user.role, 'logs.all')) {
        where.push('username = ?');
        params.push(req.user.username);
    }
    if (withUserFilters) {
        for (const column of ['entity', 'action']) {
            if (typeof req.query[column] === 'string' && req.query[column] !== '') {
                where.push(`${column} = ?`);
                params.push(req.query[column]);
            }
        }
        if (typeof req.query.q === 'string' && req.query.q.trim() !== '') {
            where.push('(detail LIKE ? OR username LIKE ? OR ip LIKE ?)');
            const like = `%${req.query.q.trim()}%`;
            params.push(like, like, like);
        }
        if (Object.hasOwn(LOG_RANGES, req.query.range)) where.push(LOG_RANGES[req.query.range]);
    }
    return { where, params, whereSql: where.length > 0 ? `WHERE ${where.join(' AND ')}` : '' };
}

app.get('/api/admin/logs', requirePerm('logs.own', 'logs.all'), asyncRoute(async (req, res) => {
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 200);
    const offset = Math.max(Number.parseInt(req.query.offset, 10) || 0, 0);
    const { params, whereSql } = buildLogFilter(req);

    const [[countRow]] = await pdb.query(`SELECT COUNT(*) AS total FROM activity_logs ${whereSql}`, params);
    const [rows] = await pdb.query(
        `SELECT id, action, entity, entity_id, detail, username, ip, created_at
         FROM activity_logs ${whereSql} ORDER BY id DESC LIMIT ? OFFSET ?`,
        [...params, limit, offset]);
    res.json({ total: countRow.total, limit, offset, rows });
}));

// สรุปตัวเลขหน้า System Logs (นับเฉพาะ log ที่ผู้ใช้คนนี้มีสิทธิ์เห็น)
app.get('/api/admin/logs/summary', requirePerm('logs.own', 'logs.all'), asyncRoute(async (req, res) => {
    const { where, params } = buildLogFilter(req, { withUserFilters: false });
    const scope = where.length > 0 ? `${where.join(' AND ')} AND ` : '';
    const [[row]] = await pdb.query(`
        SELECT
            SUM(action = 'login' AND created_at >= CURDATE()) AS logins_today,
            SUM(action = 'login' AND created_at >= CURDATE() - INTERVAL 1 DAY AND created_at < CURDATE()) AS logins_yesterday,
            SUM(action NOT IN ('login', 'login_failed', 'logout') AND created_at >= CURDATE()) AS edits_today,
            SUM(action NOT IN ('login', 'login_failed', 'logout') AND created_at >= NOW() - INTERVAL 7 DAY) AS edits_7d,
            SUM(action = 'login_failed' AND created_at >= NOW() - INTERVAL 1 DAY) AS failed_24h,
            COUNT(*) AS total,
            MIN(created_at) AS oldest
        FROM activity_logs WHERE ${scope} 1 = 1`, params);
    res.json({
        logins_today: Number(row.logins_today) || 0, logins_yesterday: Number(row.logins_yesterday) || 0,
        edits_today: Number(row.edits_today) || 0, edits_7d: Number(row.edits_7d) || 0,
        failed_24h: Number(row.failed_24h) || 0, total: Number(row.total) || 0, oldest: row.oldest,
    });
}));

const LOG_EXPORT_MAX = 5000;

app.get('/api/admin/logs/export.csv', requirePerm('logs.own', 'logs.all'), asyncRoute(async (req, res) => {
    const { params, whereSql } = buildLogFilter(req);
    const [rows] = await pdb.query(
        `SELECT created_at, action, entity, detail, username, ip
         FROM activity_logs ${whereSql} ORDER BY id DESC LIMIT ?`, [...params, LOG_EXPORT_MAX]);

    const lines = ['created_at,action,entity,detail,username,ip'];
    for (const item of rows) {
        lines.push([item.created_at.toISOString(), item.action, item.entity, item.detail, item.username, item.ip].map(csvCell).join(','));
    }
    const stamp = new Date().toISOString().slice(0, 10).replaceAll('-', '');
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="activity-logs-${stamp}.csv"`);
    res.send(`${String.fromCharCode(0xFEFF)}${lines.join('\r\n')}\r\n`); // BOM ให้ Excel อ่านภาษาไทยถูก

    logActivity(req, { action: 'export', entity: 'admin', detail: `ส่งออกบันทึกกิจกรรมเป็น CSV ${rows.length} รายการ` });
}));

// เช็กสุขภาพระบบจริง: ฐานข้อมูลตอบสนอง + โฟลเดอร์เก็บรูปเขียนไฟล์ได้ (ใช้แสดงสถานะบนแถบบนของแดชบอร์ด)
app.get('/api/admin/health', requireAuth, asyncRoute(async (req, res) => {
    let database = false;
    try {
        await pdb.query('SELECT 1');
        database = true;
    } catch (err) {
        console.error('health check: ฐานข้อมูลไม่ตอบสนอง', err.message);
    }
    const storage = [FLOORPLAN_DIR, PANORAMA_DIR, COVER_DIR, TOUR_IMAGE_DIR].every((dir) => {
        try {
            fs.accessSync(dir, fs.constants.W_OK);
            return true;
        } catch (err) {
            return false;
        }
    });
    // จำนวนล็อกอินไม่สำเร็จใน 24 ชม. ล่าสุดใช้โชว์จุดแดงที่กระดิ่ง เห็นเฉพาะ admin (บทบาทที่ไม่มีสิทธิ์ดู log ของคนอื่นจะไม่เห็น)
    let failedLogins24h = 0;
    if (database && hasPermission(req.user.role, 'logs.all')) {
        const [[row]] = await pdb.query(
            "SELECT COUNT(*) AS total FROM activity_logs WHERE action = 'login_failed' AND created_at >= NOW() - INTERVAL 1 DAY");
        failedLogins24h = row.total;
    }
    res.json({ database, storage, ok: database && storage, failed_logins_24h: failedLogins24h });
}));

// สรุปสถิติภาพรวมสำหรับหน้า Overview ของ Admin Dashboard
app.get('/api/admin/overview', requirePerm('overview.view'), asyncRoute(async (req, res) => {
    const [[stats]] = await pdb.query(`
        SELECT
            (SELECT COUNT(*) FROM buildings) AS building_count,
            (SELECT COUNT(*) FROM rooms) AS room_count,
            (SELECT COUNT(*) FROM rooms WHERE status = 'active') AS active_room_count,
            (SELECT COUNT(*) FROM rooms WHERE status = 'maintenance') AS maintenance_room_count,
            (SELECT COUNT(DISTINCT room_id) FROM panoramas) AS rooms_with_panorama_count,
            (SELECT COUNT(*) FROM rooms WHERE pin_x IS NOT NULL AND pin_y IS NOT NULL) AS pinned_room_count,
            (SELECT COUNT(*) FROM floor_plans) AS floor_plan_count,
            (SELECT COUNT(*) FROM buildings WHERE created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')) AS buildings_this_month,
            (SELECT COUNT(*) FROM activity_logs) AS log_total,
            (SELECT COUNT(*) FROM activity_logs WHERE action = 'login_failed'
                AND created_at >= NOW() - INTERVAL 1 DAY) AS failed_logins_24h
    `);
    const [recentActivity] = await pdb.query(
        'SELECT id, action, entity, detail, username, ip, created_at FROM activity_logs ORDER BY id DESC LIMIT 5');

    // "สิ่งที่ต้องดำเนินการ": ห้องที่ยังไม่มีภาพ 360° และห้องที่ปิดปรับปรุงอยู่ (อย่างละไม่เกิน 5 ห้อง)
    const [roomsWithoutPanorama] = await pdb.query(`
        SELECT rooms.id, rooms.room_code, rooms.floor, buildings.name AS building_name
        FROM rooms JOIN buildings ON buildings.id = rooms.building_id
        WHERE rooms.status = 'active'
          AND NOT EXISTS (SELECT 1 FROM panoramas WHERE panoramas.room_id = rooms.id)
        ORDER BY buildings.name, rooms.floor, rooms.room_code LIMIT 5
    `);
    const [maintenanceRooms] = await pdb.query(`
        SELECT rooms.id, rooms.room_code, rooms.floor, buildings.name AS building_name
        FROM rooms JOIN buildings ON buildings.id = rooms.building_id
        WHERE rooms.status = 'maintenance'
        ORDER BY buildings.name, rooms.floor, rooms.room_code LIMIT 5
    `);
    // ข้อมูลจาก log (กิจกรรมล่าสุด จำนวนล็อกอินผิด) ส่งให้เฉพาะบทบาทที่ดู log ของทุกคนได้
    const seesAllLogs = hasPermission(req.user.role, 'logs.all');
    res.json({
        ...stats,
        log_total: seesAllLogs ? stats.log_total : 0,
        failed_logins_24h: seesAllLogs ? stats.failed_logins_24h : 0,
        recent_activity: seesAllLogs ? recentActivity : [],
        rooms_without_panorama: roomsWithoutPanorama, maintenance_rooms: maintenanceRooms,
    });
}));

// ข้อผิดพลาดที่ไม่ได้ดักไว้ (เช่น JSON เสียรูป, body ใหญ่เกิน) ให้ตอบเป็น JSON เสมอ
app.use((err, req, res, next) => {
    if (err?.type === 'entity.too.large') {
        return res.status(413).json({ error: 'ข้อมูลที่ส่งมามีขนาดใหญ่เกินไป' });
    }
    if (err?.type === 'entity.parse.failed') {
        return res.status(400).json({ error: 'รูปแบบข้อมูล JSON ไม่ถูกต้อง' });
    }
    console.error(err);
    res.status(err?.status ? err.status : 500).json({ error: 'เกิดข้อผิดพลาดภายในระบบ' });
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
    `CREATE TABLE IF NOT EXISTS admin_roles (
        role_key VARCHAR(40) NOT NULL,
        label VARCHAR(60) NOT NULL,
        label_th VARCHAR(100) NOT NULL DEFAULT '',
        description VARCHAR(300) NOT NULL DEFAULT '',
        permissions TEXT NOT NULL,
        is_system TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (role_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
    `CREATE TABLE IF NOT EXISTS admin_users (
        id INT NOT NULL AUTO_INCREMENT,
        username VARCHAR(50) NOT NULL,
        password_hash VARCHAR(100) NOT NULL,
        role VARCHAR(30) NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'active',
        full_name VARCHAR(100) NOT NULL DEFAULT '',
        email VARCHAR(120) NOT NULL DEFAULT '',
        phone VARCHAR(40) NOT NULL DEFAULT '',
        department VARCHAR(150) NOT NULL DEFAULT '',
        avatar MEDIUMTEXT DEFAULT NULL,
        last_login_at TIMESTAMP NULL DEFAULT NULL,
        last_login_ip VARCHAR(64) DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_admin_users_username (username)
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

// ใส่บทบาทตั้งต้นที่ยังไม่มีในฐานข้อมูล (ไม่เขียนทับบทบาทที่ถูกแก้ไขแล้ว) แล้วโหลดเข้าหน่วยความจำ
async function seedAdminRoles() {
    for (const role of DEFAULT_ROLES) {
        await pdb.query(
            `INSERT IGNORE INTO admin_roles (role_key, label, label_th, description, permissions, is_system)
             VALUES (?, ?, ?, ?, ?, 1)`,
            [role.key, role.label, role.label_th, role.description, JSON.stringify(normalizePermissions(role.permissions))]);
    }
    await reloadRoles();
}

// ครั้งแรกที่ตาราง admin_users ว่าง: สร้างบัญชี admin และ editor เดิมจาก environment (ใช้รหัสผ่านและโปรไฟล์ที่เคยเปลี่ยนไว้ใน admin_settings ถ้ามี)
async function seedAdminUsers() {
    const [[{ total }]] = await pdb.query('SELECT COUNT(*) AS total FROM admin_users');
    if (total > 0) return;
    const readSetting = async (key) => {
        const [rows] = await pdb.query('SELECT setting_value FROM admin_settings WHERE setting_key = ?', [key]);
        return rows.length > 0 ? rows[0].setting_value : null;
    };
    const legacyAccounts = [
        { username: ADMIN_USERNAME, role: 'admin', hashKey: 'admin_password_hash', defaultHash: ADMIN_PASSWORD_HASH, profileKey: 'profile_admin' },
        { username: EDITOR_USERNAME, role: 'panorama_editor', hashKey: 'editor_password_hash', defaultHash: EDITOR_PASSWORD_HASH, profileKey: 'profile_editor' },
    ];
    for (const account of legacyAccounts) {
        let profile = {};
        try { profile = JSON.parse(await readSetting(account.profileKey) || '{}') || {}; } catch (err) { profile = {}; }
        const text = (key) => (typeof profile[key] === 'string' ? profile[key] : '');
        await pdb.query(
            `INSERT IGNORE INTO admin_users (username, password_hash, role, full_name, email, phone, department, avatar)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [account.username.toLowerCase(), (await readSetting(account.hashKey)) || account.defaultHash, account.role,
                text('full_name'), text('email'), text('phone'), text('department'), typeof profile.avatar === 'string' ? profile.avatar : null]);
    }
    console.log('✅ สร้างบัญชีผู้ดูแลตั้งต้นจาก environment แล้ว');
}

async function ensureDashboardSchema(attempt = 1) {
    try {
        const [existing] = await pdb.query("SHOW TABLES LIKE 'floor_plans'");
        const floorPlansIsNew = existing.length === 0;

        for (const statement of DASHBOARD_TABLES) {
            await pdb.query(statement);
        }
        // คอลัมน์ 2FA / ล็อกบัญชี / อายุรหัสผ่าน เพิ่มให้ตาราง admin_users ที่สร้างไว้ก่อนมีฟีเจอร์ความปลอดภัย
        const USER_SECURITY_COLUMNS = [
            ['totp_secret', 'VARCHAR(64) DEFAULT NULL'], ['totp_enabled', 'TINYINT(1) NOT NULL DEFAULT 0'],
            ['totp_last_step', 'BIGINT DEFAULT NULL'], ['backup_codes', 'TEXT DEFAULT NULL'],
            ['failed_attempts', 'INT NOT NULL DEFAULT 0'], ['locked_until', 'TIMESTAMP NULL DEFAULT NULL'],
            ['password_changed_at', 'TIMESTAMP NULL DEFAULT NULL'],
        ];
        for (const [column, definition] of USER_SECURITY_COLUMNS) {
            const [found] = await pdb.query('SHOW COLUMNS FROM admin_users LIKE ?', [column]);
            if (found.length === 0) await pdb.query(`ALTER TABLE admin_users ADD COLUMN ${column} ${definition}`);
        }
        // คอลัมน์รูปปกอาคาร เพิ่มให้ฐานข้อมูลเดิมที่สร้างก่อนมีฟีเจอร์นี้
        const [coverColumn] = await pdb.query("SHOW COLUMNS FROM buildings LIKE 'cover_image'");
        if (coverColumn.length === 0) {
            await pdb.query('ALTER TABLE buildings ADD COLUMN cover_image VARCHAR(500) DEFAULT NULL');
        }
        await seedAdminRoles();
        await seedAdminUsers();
        await pdb.query('UPDATE admin_users SET password_changed_at = NOW() WHERE password_changed_at IS NULL');
        await reloadSecuritySettings();
        await reloadSystemSettings();
        await loadBackupSettings();
        startBackupScheduler();
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
