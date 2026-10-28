const { escape } = require('mysql2');
const { toSqlLiteral } = require('../lib/sql-dump');

const literal = (value) => toSqlLiteral(value, escape);

describe('toSqlLiteral', () => {
    test('ค่าทั่วไปเหมือน escape ปกติ', () => {
        expect(literal(null)).toBe('NULL');
        expect(literal(5)).toBe('5');
        expect(literal("it's")).toBe("'it\\'s'");
        expect(literal('ห้อง 201')).toBe("'ห้อง 201'");
    });

    test('ออบเจ็กต์จากคอลัมน์ JSON ถูกแปลงเป็นสตริง JSON (ไม่ใช่ `key` = value)', () => {
        const hours = { mon: { open: '08:00', close: '20:00' }, sun: null };
        const sql = literal(hours);
        expect(sql.startsWith("'") && sql.endsWith("'")).toBe(true);
        expect(JSON.parse(sql.slice(1, -1).replaceAll("\\'", "'").replaceAll('\\"', '"'))).toEqual(hours);
        expect(sql).not.toContain('`');
    });

    test('อาร์เรย์จากคอลัมน์ JSON ถูกแปลงเป็นสตริง JSON (ไม่ใช่รายการค่า a, b)', () => {
        expect(literal(['wifi', 'projector'])).toBe(escape('["wifi","projector"]'));
    });

    test('Date และ Buffer ไม่ถูกแปลงเป็น JSON', () => {
        const date = new Date('2026-10-28T10:00:00Z');
        expect(literal(date)).toBe(escape(date));
        expect(literal(Buffer.from('ab'))).toBe(escape(Buffer.from('ab')));
    });
});
