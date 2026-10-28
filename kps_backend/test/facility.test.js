const { FACILITY_WORDS, facilitySql } = require('../lib/facility');

describe('FACILITY_WORDS', () => {
    test('มีคำของห้องน้ำ ลิฟต์ บันได โถง ร้านค้า สำนักงาน ห้องสมุด (ต้องตรงกับแอป Flutter และแดชบอร์ด)', () => {
        expect(FACILITY_WORDS).toEqual(['ห้องน้ำ', 'ลิฟต์', 'บันได', 'โถง', 'ร้านค้า', 'โรงอาหาร', 'สำนักงาน', 'ห้องสมุด', 'อ่านหนังสือ']);
    });
});

describe('facilitySql', () => {
    test('ใช้ตาราง rooms เป็นค่าเริ่มต้น และไม่นับแถวที่ไม่มีห้อง (LEFT JOIN ว่าง)', () => {
        const sql = facilitySql();
        expect(sql.startsWith('(rooms.id IS NOT NULL AND (')).toBe(true);
        expect(sql).toContain("CONCAT_WS(' ', rooms.room_type, rooms.room_code) LIKE '%ห้องน้ำ%'");
    });

    test('รองรับชื่อตารางอื่น', () => {
        expect(facilitySql('r')).toContain("CONCAT_WS(' ', r.room_type, r.room_code) LIKE '%ลิฟต์%'");
    });

    test('มีเงื่อนไขครบทุกคำ เชื่อมด้วย OR', () => {
        const sql = facilitySql('r');
        expect(sql.match(/ LIKE /g)).toHaveLength(FACILITY_WORDS.length);
        expect(sql.match(/ OR /g)).toHaveLength(FACILITY_WORDS.length - 1);
    });
});
