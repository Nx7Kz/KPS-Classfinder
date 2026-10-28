const crypto = require('node:crypto');
const { base32Encode, base32Decode, hotp, verifyTotp } = require('../lib/totp');

describe('base32', () => {
    test('เข้ารหัสตามตัวอย่างใน RFC 4648', () => {
        expect(base32Encode(Buffer.from('foobar'))).toBe('MZXW6YTBOI');
        expect(base32Encode(Buffer.from('f'))).toBe('MY');
        expect(base32Encode(Buffer.alloc(0))).toBe('');
    });

    test('ถอดรหัสได้ข้อมูลเดิม ไม่สนตัวพิมพ์เล็ก/ใหญ่และเครื่องหมาย = ท้ายสตริง', () => {
        expect(base32Decode('MZXW6YTBOI').toString()).toBe('foobar');
        expect(base32Decode('mzxw6ytboi').toString()).toBe('foobar');
        expect(base32Decode('MY======').toString()).toBe('f');
    });

    test('ข้ามอักขระที่ไม่อยู่ในตัวอักษร base32', () => {
        expect(base32Decode('MZXW 6YTB-OI').toString()).toBe('foobar');
    });

    test('เข้ารหัสแล้วถอดกลับได้ค่าเดิมกับข้อมูลสุ่ม', () => {
        const data = crypto.randomBytes(20);
        expect(base32Decode(base32Encode(data)).equals(data)).toBe(true);
    });
});

describe('hotp (RFC 4226 Appendix D)', () => {
    const secret = Buffer.from('12345678901234567890');
    const expected = ['755224', '287082', '359152', '969429', '338314', '254676', '287922', '162583', '399871', '520489'];

    test.each(expected.map((code, counter) => [counter, code]))('counter %i = %s', (counter, code) => {
        expect(hotp(secret, counter)).toBe(code);
    });
});

describe('verifyTotp', () => {
    const secretBase32 = base32Encode(Buffer.from('12345678901234567890'));
    const secret = base32Decode(secretBase32);
    const NOW = 1_700_000_000_000;
    const step = Math.floor(NOW / 30000);

    beforeEach(() => jest.spyOn(Date, 'now').mockReturnValue(NOW));
    afterEach(() => jest.restoreAllMocks());

    test('รหัสของช่วงเวลาปัจจุบันผ่าน และคืนเลข step', () => {
        expect(verifyTotp(secretBase32, hotp(secret, step))).toBe(step);
    });

    test('รับรหัสที่เลื่อนไป ±1 ช่วงเวลา (นาฬิกาเครื่องคลาดเคลื่อน)', () => {
        expect(verifyTotp(secretBase32, hotp(secret, step - 1))).toBe(step - 1);
        expect(verifyTotp(secretBase32, hotp(secret, step + 1))).toBe(step + 1);
    });

    test('ไม่รับรหัสที่เลื่อนเกิน 1 ช่วงเวลา', () => {
        expect(verifyTotp(secretBase32, hotp(secret, step + 2))).toBeNull();
    });

    test('ไม่รับ step ที่เคยใช้แล้ว (กันใช้รหัสซ้ำ)', () => {
        expect(verifyTotp(secretBase32, hotp(secret, step), step)).toBeNull();
        expect(verifyTotp(secretBase32, hotp(secret, step), step - 1)).toBe(step);
    });

    test('ยอมให้มีช่องว่างในรหัส เช่น "123 456"', () => {
        const code = hotp(secret, step);
        expect(verifyTotp(secretBase32, `${code.slice(0, 3)} ${code.slice(3)}`)).toBe(step);
    });

    test.each([undefined, null, '', '12345', '1234567', 'abcdef'])('รูปแบบรหัสไม่ถูกต้อง (%p) ถูกปฏิเสธ', (value) => {
        expect(verifyTotp(secretBase32, value)).toBeNull();
    });

    test('รหัสผิดถูกปฏิเสธ', () => {
        const wrong = hotp(secret, step) === '000000' ? '000001' : '000000';
        expect(verifyTotp(secretBase32, wrong)).toBeNull();
    });
});
