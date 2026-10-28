const crypto = require('node:crypto');

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
    let end = text.length;
    while (end > 0 && text[end - 1] === '=') end -= 1;
    for (const char of text.slice(0, end).toUpperCase()) {
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

module.exports = { base32Encode, base32Decode, hotp, verifyTotp };
