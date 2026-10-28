const {
    WEEK_KEYS, parseOpenHours, sanitizeOpenHours, bangkokParts, shiftDate, timeToMinutes,
    setClosures, findClosure, getOpenStatus,
} = require('../lib/open-hours');

// ทุกเวลาในเทสต์เป็นเวลาไทย (UTC+7): 2026-11-02 เป็นวันจันทร์
const thai = (iso) => new Date(`${iso}+07:00`);
const weekdayHours = (open = '08:00', close = '20:00') => ({
    sun: null, mon: { open, close }, tue: { open, close }, wed: { open, close }, thu: { open, close }, fri: { open, close }, sat: null,
});

afterEach(() => setClosures([]));

describe('parseOpenHours', () => {
    test('null/undefined = ไม่กำหนด', () => {
        expect(parseOpenHours(null)).toBeNull();
        expect(parseOpenHours(undefined)).toBeNull();
    });

    test('รับทั้งสตริง JSON และออบเจ็กต์', () => {
        const hours = weekdayHours();
        expect(parseOpenHours(JSON.stringify(hours))).toEqual(hours);
        expect(parseOpenHours(hours)).toBe(hours);
    });

    test('สตริงเสียหรือค่าที่ไม่ใช่ออบเจ็กต์ = null', () => {
        expect(parseOpenHours('{เสีย')).toBeNull();
        expect(parseOpenHours('123')).toBeNull();
        expect(parseOpenHours(5)).toBeNull();
    });
});

describe('sanitizeOpenHours', () => {
    test('ไม่ส่งมา = ไม่กำหนดเวลาทำการ', () => {
        expect(sanitizeOpenHours(null)).toEqual({ value: null });
        expect(sanitizeOpenHours(undefined)).toEqual({ value: null });
    });

    test('ข้อมูลที่ถูกต้อง: วันที่ไม่ส่งมาเป็น null (ปิด) และตัดฟิลด์เกินทิ้ง', () => {
        const result = sanitizeOpenHours({ mon: { open: '08:00', close: '16:30', extra: 'x' } });
        expect(result.value.mon).toEqual({ open: '08:00', close: '16:30' });
        expect(result.value.sun).toBeNull();
        expect(Object.keys(result.value)).toEqual(WEEK_KEYS);
    });

    test.each([[[]], ['text'], [5]])('รูปแบบไม่ถูกต้อง (%p)', (input) => {
        expect(sanitizeOpenHours(input).error).toBe('รูปแบบเวลาทำการไม่ถูกต้อง');
    });

    test('เวลาผิดรูปแบบ HH:MM', () => {
        expect(sanitizeOpenHours({ mon: { open: '8:00', close: '16:00' } }).error).toContain('วันจันทร์');
        expect(sanitizeOpenHours({ tue: { open: '08:00', close: '24:00' } }).error).toContain('วันอังคาร');
        expect(sanitizeOpenHours({ wed: 'เปิด' }).error).toContain('วันพุธ');
    });

    test('เวลาปิดต้องอยู่หลังเวลาเปิด', () => {
        expect(sanitizeOpenHours({ thu: { open: '16:00', close: '08:00' } }).error).toBe('วันพฤหัสบดี: เวลาปิดต้องอยู่หลังเวลาเปิด');
        expect(sanitizeOpenHours({ fri: { open: '08:00', close: '08:00' } }).error).toContain('วันศุกร์');
    });
});

describe('เวลาตามเขตเวลาไทย', () => {
    test('bangkokParts ข้ามเที่ยงคืนตามเวลาไทย ไม่ใช่ UTC', () => {
        // 2026-11-02 23:30 เวลาไทย = 16:30 UTC (ยังเป็นวันที่ 2 ทั้งคู่) ส่วน 00:10 ไทย = 17:10 UTC ของวันก่อนหน้า
        expect(bangkokParts(thai('2026-11-02T23:30:00'))).toEqual({ date: '2026-11-02', day: 1, minutes: 23 * 60 + 30 });
        expect(bangkokParts(thai('2026-11-03T00:10:00'))).toEqual({ date: '2026-11-03', day: 2, minutes: 10 });
    });

    test('shiftDate เลื่อนวันและคืนวันในสัปดาห์', () => {
        expect(shiftDate('2026-11-02', 1)).toEqual({ date: '2026-11-03', day: 2 });
        expect(shiftDate('2026-12-31', 1)).toEqual({ date: '2027-01-01', day: 5 });
        expect(shiftDate('2026-11-02', 0)).toEqual({ date: '2026-11-02', day: 1 });
    });

    test('timeToMinutes', () => {
        expect(timeToMinutes('00:00')).toBe(0);
        expect(timeToMinutes('08:30')).toBe(510);
        expect(timeToMinutes('23:59')).toBe(1439);
    });
});

describe('findClosure', () => {
    const building = { id: 1, building_id: 7, room_id: null, start_date: '2026-11-01', end_date: '2026-11-05', reason: 'อาคาร' };
    const room = { id: 2, building_id: null, room_id: 3, start_date: '2026-11-02', end_date: '2026-11-02', reason: 'ห้อง' };
    const everywhere = { id: 3, building_id: null, room_id: null, start_date: '2026-11-02', end_date: '2026-11-02', reason: 'ทั้งมหาวิทยาลัย' };

    test('ไม่มีวันปิดตรงวัน = null', () => {
        setClosures([building]);
        expect(findClosure('2026-11-10', 3, 7)).toBeNull();
    });

    test('ระดับห้องเด่นกว่าอาคาร และอาคารเด่นกว่าทั้งมหาวิทยาลัย', () => {
        setClosures([everywhere, building, room]);
        expect(findClosure('2026-11-02', 3, 7).reason).toBe('ห้อง');
        expect(findClosure('2026-11-02', 99, 7).reason).toBe('อาคาร');
        expect(findClosure('2026-11-02', 99, 99).reason).toBe('ทั้งมหาวิทยาลัย');
    });

    test('วันปิดของห้อง/อาคารอื่นไม่มีผล', () => {
        setClosures([room, { ...building, building_id: 8 }]);
        expect(findClosure('2026-11-02', 4, 7)).toBeNull();
    });
});

describe('getOpenStatus', () => {
    const base = { hours: weekdayHours(), roomId: 3, buildingId: 7 };

    test('สถานะของห้องมาก่อนเวลาทำการ', () => {
        expect(getOpenStatus({ ...base, status: 'maintenance', statusReason: 'ซ่อมแอร์' }, thai('2026-11-02T10:00:00')))
            .toMatchObject({ state: 'closed', reason: 'maintenance', label: 'ปิดปรับปรุง', detail: 'ซ่อมแอร์' });
        expect(getOpenStatus({ ...base, status: 'suspended' }, thai('2026-11-02T10:00:00')))
            .toMatchObject({ reason: 'suspended', label: 'งดใช้งาน', detail: null });
        expect(getOpenStatus({ ...base, status: 'inactive' }, thai('2026-11-02T10:00:00')))
            .toMatchObject({ reason: 'inactive', label: 'ปิดใช้งาน' });
    });

    test('วันปิดพิเศษมาก่อนเวลาทำการ', () => {
        setClosures([{ id: 1, building_id: 7, room_id: null, start_date: '2026-11-02', end_date: '2026-11-04', reason: 'สอบ' }]);
        expect(getOpenStatus(base, thai('2026-11-02T10:00:00')))
            .toMatchObject({ state: 'closed', reason: 'closure', detail: 'สอบ', until: '2026-11-04' });
    });

    test('ไม่มีเวลาทำการ = ไม่ระบุ', () => {
        expect(getOpenStatus({ hours: null }, thai('2026-11-02T10:00:00'))).toEqual({ state: 'unknown', label: 'ไม่ระบุเวลาทำการ' });
    });

    test('อยู่ในเวลาทำการ = เปิดอยู่ (เวลาเปิดนับ เวลาปิดไม่นับ)', () => {
        expect(getOpenStatus(base, thai('2026-11-02T08:00:00'))).toMatchObject({ state: 'open', closes_at: '20:00' });
        expect(getOpenStatus(base, thai('2026-11-02T19:59:00'))).toMatchObject({ state: 'open' });
        expect(getOpenStatus(base, thai('2026-11-02T20:00:00')).state).toBe('closed');
    });

    test('ก่อนเปิดวันนี้ = บอกว่าเปิดวันนี้กี่โมง', () => {
        expect(getOpenStatus(base, thai('2026-11-02T06:00:00')))
            .toMatchObject({ state: 'closed', reason: 'hours', label: 'ปิดอยู่ · เปิดวันนี้ 08:00 น.', opens_in_days: 0 });
    });

    test('หลังปิดวันนี้ = เปิดพรุ่งนี้', () => {
        expect(getOpenStatus(base, thai('2026-11-02T21:00:00')))
            .toMatchObject({ label: 'ปิดอยู่ · เปิดพรุ่งนี้ 08:00 น.', opens_at: '08:00', opens_in_days: 1 });
    });

    test('ศุกร์ค่ำ = เปิดวันจันทร์ (ข้ามเสาร์-อาทิตย์)', () => {
        expect(getOpenStatus(base, thai('2026-11-06T21:00:00')))
            .toMatchObject({ label: 'ปิดอยู่ · เปิดวันจันทร์ 08:00 น.', opens_in_days: 3 });
    });

    test('ข้ามวันที่มีวันปิดพิเศษไปหาวันเปิดถัดไป', () => {
        setClosures([{ id: 1, building_id: 7, room_id: null, start_date: '2026-11-03', end_date: '2026-11-03', reason: 'หยุด' }]);
        expect(getOpenStatus(base, thai('2026-11-02T21:00:00')))
            .toMatchObject({ label: 'ปิดอยู่ · เปิดวันพุธ 08:00 น.', opens_in_days: 2 });
    });

    test('ไม่มีวันเปิดภายใน 7 วัน = ปิดทำการ', () => {
        const never = Object.fromEntries(WEEK_KEYS.map((key) => [key, null]));
        expect(getOpenStatus({ hours: never }, thai('2026-11-02T10:00:00'))).toEqual({ state: 'closed', reason: 'hours', label: 'ปิดทำการ' });
    });
});
