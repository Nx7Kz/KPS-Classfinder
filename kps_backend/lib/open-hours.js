const WEEK_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
const WEEK_LABELS_TH = ['วันอาทิตย์', 'วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์'];
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
let closuresCache = [];
const setClosures = (rows) => { closuresCache = rows; };

function parseOpenHours(value) {
    if (value === null || value === undefined) return null;
    let parsed = value;
    if (typeof parsed === 'string') {
        try { parsed = JSON.parse(parsed); } catch (err) { return null; }
    }
    return parsed && typeof parsed === 'object' ? parsed : null;
}

// คืน { value } เมื่อถูกต้อง (null = ไม่กำหนดเวลาทำการ) หรือ { error }
function sanitizeOpenHours(input) {
    if (input === null || input === undefined) return { value: null };
    if (typeof input !== 'object' || Array.isArray(input)) return { error: 'รูปแบบเวลาทำการไม่ถูกต้อง' };
    const result = {};
    for (let index = 0; index < WEEK_KEYS.length; index += 1) {
        const key = WEEK_KEYS[index];
        const day = input[key];
        if (day === null || day === undefined) {
            result[key] = null;
            continue;
        }
        if (typeof day !== 'object' || !TIME_PATTERN.test(day.open) || !TIME_PATTERN.test(day.close)) {
            return { error: `เวลาทำการของ${WEEK_LABELS_TH[index]}ไม่ถูกต้อง (ต้องเป็นรูปแบบ HH:MM)` };
        }
        if (day.open >= day.close) return { error: `${WEEK_LABELS_TH[index]}: เวลาปิดต้องอยู่หลังเวลาเปิด` };
        result[key] = { open: day.open, close: day.close };
    }
    return { value: result };
}

// วัน/เวลาตามเขตเวลาไทย (UTC+7 ไม่มี DST) ไม่ขึ้นกับเขตเวลาของเครื่องเซิร์ฟเวอร์
function bangkokParts(at = new Date()) {
    const shifted = new Date(at.getTime() + 7 * 3600 * 1000);
    return { date: shifted.toISOString().slice(0, 10), day: shifted.getUTCDay(), minutes: shifted.getUTCHours() * 60 + shifted.getUTCMinutes() };
}

function shiftDate(dateString, offset) {
    const shifted = new Date(`${dateString}T00:00:00Z`);
    shifted.setUTCDate(shifted.getUTCDate() + offset);
    return { date: shifted.toISOString().slice(0, 10), day: shifted.getUTCDay() };
}

const timeToMinutes = value => Number(value.slice(0, 2)) * 60 + Number(value.slice(3, 5));

// วันปิดที่ตรงวันนั้น: ระดับห้องเด่นกว่าระดับอาคาร และระดับอาคารเด่นกว่าทั้งมหาวิทยาลัย
function findClosure(dateString, roomId, buildingId) {
    let best = null;
    let bestRank = 0;
    for (const closure of closuresCache) {
        if (dateString < closure.start_date || dateString > closure.end_date) continue;
        let rank = 1;
        if (closure.room_id) rank = closure.room_id === roomId ? 3 : 0;
        else if (closure.building_id) rank = closure.building_id === buildingId ? 2 : 0;
        if (rank > bestRank) {
            best = closure;
            bestRank = rank;
        }
    }
    return best;
}

// หาวันและเวลาเปิดครั้งถัดไป (ภายใน 7 วัน) คืน null เมื่อไม่พบ
function findNextOpening(hours, now, roomId, buildingId) {
    for (let offset = 0; offset <= 7; offset += 1) {
        const target = offset === 0 ? { date: now.date, day: now.day } : shiftDate(now.date, offset);
        const slot = hours[WEEK_KEYS[target.day]];
        if (!slot) continue;
        if (offset === 0 && now.minutes >= timeToMinutes(slot.open)) continue; // เลยเวลาปิดของวันนี้ไปแล้ว
        if (offset > 0 && findClosure(target.date, roomId, buildingId)) continue;
        let when = WEEK_LABELS_TH[target.day];
        if (offset === 0) when = 'วันนี้';
        else if (offset === 1) when = 'พรุ่งนี้';
        return { state: 'closed', reason: 'hours', label: `ปิดอยู่ · เปิด${when} ${slot.open} น.`, opens_at: slot.open, opens_in_days: offset };
    }
    return null;
}

function getOpenStatus({ status = 'active', statusReason = null, hours = null, roomId = null, buildingId = null }, at = new Date()) {
    if (status === 'maintenance') return { state: 'closed', reason: 'maintenance', label: 'ปิดปรับปรุง', detail: statusReason || null };
    if (status === 'suspended') return { state: 'closed', reason: 'suspended', label: 'งดใช้งาน', detail: statusReason || null };
    if (status === 'inactive') return { state: 'closed', reason: 'inactive', label: 'ปิดใช้งาน' };
    const now = bangkokParts(at);
    const closure = findClosure(now.date, roomId, buildingId);
    if (closure) {
        return { state: 'closed', reason: 'closure', label: 'ปิดทำการ', detail: closure.reason || null, until: closure.end_date };
    }
    if (!hours) return { state: 'unknown', label: 'ไม่ระบุเวลาทำการ' };

    const today = hours[WEEK_KEYS[now.day]];
    if (today && now.minutes >= timeToMinutes(today.open) && now.minutes < timeToMinutes(today.close)) {
        return { state: 'open', label: `เปิดอยู่ · ปิด ${today.close} น.`, closes_at: today.close };
    }
    const next = findNextOpening(hours, now, roomId, buildingId);
    if (next) return next;
    return { state: 'closed', reason: 'hours', label: 'ปิดทำการ' };
}

module.exports = {
    WEEK_KEYS, WEEK_LABELS_TH, TIME_PATTERN,
    parseOpenHours, sanitizeOpenHours, bangkokParts, shiftDate, timeToMinutes,
    setClosures, findClosure, findNextOpening, getOpenStatus,
};
