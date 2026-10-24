// หน้า /tour/?building=<id>[&point=<id>|&room=<id>][&embed=app]
// embed=app = เปิดในแอป Flutter (WebView) ส่งข้อความกลับผ่าน channel "KpsApp" เช่น ปุ่มปิด
import { createTourViewer, prepareTour, escapeHtml } from './tour.js';

const params = new URLSearchParams(location.search);
const buildingId = Number(params.get('building'));
const inApp = params.get('embed') === 'app';
const theme = params.get('theme');
if (theme === 'dark' || theme === 'light') document.documentElement.dataset.theme = theme;
document.body.classList.toggle('in-app', inApp);

const $ = (id) => document.getElementById(id);

// ชื่อรองของจุดที่ยืนอยู่: ป้ายชื่อที่ตั้งไว้ > หน้าห้องถ้าผูกกับห้อง > "ทางเดิน" (แยกออกมาเพื่อไม่ต้องซ้อน template literal)
function pointSubtitle(point) {
  return point.label || (point.room_code ? `หน้าห้อง ${point.room_code}` : 'ทางเดิน');
}

function postToApp(message) {
  if (window.KpsApp?.postMessage) {
    window.KpsApp.postMessage(JSON.stringify(message));
    return true;
  }
  return false;
}

function showState(text, { spinner = false } = {}) {
  $('state').hidden = false;
  $('stateText').textContent = text;
  $('state').querySelector('.kps-spinner').hidden = !spinner;
}

let toastTimer;
function toast(text) {
  const element = $('toast');
  element.textContent = text;
  element.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { element.hidden = true; }, 2200);
}

function showHintOnce() {
  try {
    if (localStorage.getItem('kps-tour-hint')) return;
    localStorage.setItem('kps-tour-hint', '1');
  } catch {
    // เก็บค่าไม่ได้ (โหมดส่วนตัว) ก็แสดงทุกครั้ง
  }
  $('hint').hidden = false;
  setTimeout(() => { $('hint').hidden = true; }, 4500);
}

$('closeButton').addEventListener('click', () => {
  if (postToApp({ type: 'close' })) return;
  if (history.length > 1) history.back();
  else window.close();
});

function renderFloors(tour, viewerApi, currentFloor) {
  const nav = $('floorSwitch');
  if (tour.tourFloors.length < 2) {
    nav.hidden = true;
    return;
  }
  nav.hidden = false;
  nav.innerHTML = tour.tourFloors
    .map((floor) => `<button type="button" data-floor="${escapeHtml(floor)}" class="${floor === currentFloor ? 'is-active' : ''}"
      aria-pressed="${floor === currentFloor}">ชั้น ${escapeHtml(floor)}</button>`)
    .join('');
  nav.querySelectorAll('button').forEach((button) => {
    button.addEventListener('click', () => {
      const floor = button.dataset.floor;
      if (floor === viewerApi.currentPoint?.floor) return;
      const target = viewerApi.nearestOnFloor(floor);
      if (target) viewerApi.goTo(target.id);
    });
  });
}

// รายการจุดในชั้นปัจจุบัน (แตะเพื่อไปดูจุดนั้น)
function setupPointsList(tour, viewerApi) {
  const sheet = $('pointsSheet');
  const close = () => { sheet.hidden = true; };
  sheet.querySelectorAll('[data-close]').forEach((element) => element.addEventListener('click', close));
  $('pointsList').addEventListener('click', (event) => {
    const item = event.target.closest('[data-point]');
    if (!item) return;
    close();
    viewerApi.goTo(Number(item.dataset.point));
  });
  $('pointsButton').addEventListener('click', () => {
    const current = viewerApi.currentPoint;
    if (!current) return;
    const floorPoints = tour.points.filter((point) => point.floor === current.floor);
    $('pointsSheetTitle').textContent = `จุดในชั้น ${current.floor} (${floorPoints.length})`;
    $('pointsList').innerHTML = floorPoints
      .map((point) => `<button type="button" class="kps-sheet-item${point.id === current.id ? ' is-current' : ''}" data-point="${point.id}">
        <span class="kps-dot"></span><span>${escapeHtml(pointSubtitle(point))}</span>${point.id === current.id ? '<small>ที่นี่</small>' : ''}</button>`)
      .join('');
    sheet.hidden = false;
  });
}

function updatePointsButton(tour, point) {
  const count = tour.points.filter((other) => other.floor === point.floor).length;
  $('pointsButton').hidden = false;
  $('pointsButtonText').textContent = `จุดในชั้นนี้ (${count})`;
}

async function main() {
  if (!Number.isInteger(buildingId) || buildingId <= 0) {
    showState('ไม่พบอาคารที่ต้องการเดินชม');
    return;
  }
  showState('กำลังโหลด…', { spinner: true });

  let data;
  try {
    const response = await fetch(`/api/tour/${buildingId}`);
    if (!response.ok) throw new Error(String(response.status));
    data = await response.json();
  } catch {
    showState('โหลดข้อมูลไม่สำเร็จ ตรวจสอบการเชื่อมต่อแล้วลองใหม่');
    return;
  }

  $('buildingName').textContent = data.building.name;
  document.title = `เดินชม ${data.building.name}`;
  if (data.points.length === 0) {
    showState('อาคารนี้ยังไม่มีจุดเดินชม');
    return;
  }

  const tour = prepareTour(data);
  const roomId = Number(params.get('room'));
  const startPoint = Number(params.get('point'))
    || data.points.find((point) => point.room_id === roomId)?.id
    || null;

  const viewerApi = createTourViewer($('viewer'), tour, {
    startPointId: startPoint,
    // แผนที่ย่อเป็นทางเลือกจุดหลัก จึงทำให้ใหญ่พอแตะจุดได้
    mapSize: window.innerWidth < 600 ? '190px' : '240px',
    onNodeChange(point) {
      $('state').hidden = true;
      $('pointName').textContent = `ชั้น ${point.floor} · ${pointSubtitle(point)}`;
      renderFloors(tour, viewerApi, point.floor);
      updatePointsButton(tour, point);
      postToApp({ type: 'point', id: point.id, floor: point.floor });
    },
  });
  viewerApi.viewer.addEventListener('panorama-error', () => toast('โหลดภาพไม่สำเร็จ'));
  setupPointsList(tour, viewerApi);
  showHintOnce();
  window.kpsTour = viewerApi; // ใช้ทดสอบ/ดีบัก
}

main();
