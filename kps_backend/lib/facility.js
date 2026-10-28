// แยก "ห้องเรียน" ออกจาก "สิ่งอำนวยความสะดวก" (ห้องน้ำ ลิฟต์ บันได โถง ร้านค้า สำนักงาน ห้องสมุด) จากประเภทห้องหรือรหัสห้อง
// ห้องที่ไม่ระบุประเภทนับเป็นห้องเรียน (กันห้องหาย) คำที่ใช้ต้องตรงกับ isFacilityRoom ใน flutter_application_1/lib/room_utils.dart
const FACILITY_WORDS = ['ห้องน้ำ', 'ลิฟต์', 'บันได', 'โถง', 'ร้านค้า', 'โรงอาหาร', 'สำนักงาน', 'ห้องสมุด', 'อ่านหนังสือ'];
const facilitySql = (alias = 'rooms') => {
    const matches = FACILITY_WORDS.map((word) => `CONCAT_WS(' ', ${alias}.room_type, ${alias}.room_code) LIKE '%${word}%'`);
    return `(${alias}.id IS NOT NULL AND (${matches.join(' OR ')}))`;
};

module.exports = { FACILITY_WORDS, facilitySql };
