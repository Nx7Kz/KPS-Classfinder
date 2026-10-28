// แปลงค่าจากคอลัมน์ให้เป็นข้อความ SQL สำหรับไฟล์สำรอง (INSERT ... VALUES)
// คอลัมน์ JSON ถูก mysql2 แปลงเป็นออบเจ็กต์/อาร์เรย์ ซึ่ง escape ตรง ๆ จะได้ SQL ผิด (`key` = 'value') และกู้คืนไม่ได้
// จึงแปลงกลับเป็นสตริง JSON ก่อน ส่วน Date/Buffer ปล่อยให้ escape จัดการตามเดิม
function toSqlLiteral(value, escape) {
    const isPlainJson = value !== null && typeof value === 'object' && !(value instanceof Date) && !Buffer.isBuffer(value);
    return escape(isPlainJson ? JSON.stringify(value) : value);
}

module.exports = { toSqlLiteral };
