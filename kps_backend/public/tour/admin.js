// ============ หน้า Virtual Tour (เดินชมอาคาร 360°) ในแดชบอร์ด ============
// ผู้ดูแลอัปโหลดภาพ 360° วางจุดบนแผนผังชั้น ตั้งชื่อ และตั้งมุมเริ่มต้น — ผู้ใช้แตะจุดบนแผนที่ย่อเพื่อดูภาพ
// ใช้ helper กลางจาก index.html: api, jsonRequest, reportError, showStatus, setBusy, escapeHtml,
// refreshBuildingList, fillSelect, floorSort, validateImageFile, buildings
/* global api, jsonRequest, reportError, showStatus, setBusy, escapeHtml, refreshBuildingList, fillSelect,
   floorSort, validateImageFile, buildings, bootstrap, SessionExpiredError */

const TOUR_MAX_UPLOAD_MB = 40;

const tourState = {
  building: null,
  floorPlans: [],
  points: [],
  rooms: [],
  zoom: 1, // ซูมแผนผังในหน้านี้ (1 = พอดีจอ)
  selectedId: null,
  placingId: null, // จุดที่กำลังรอคลิกวางบนแผนผัง
  requestId: 0,
};
let tourViewModal;
let tourViewer = null;

function initTourPage() {
  const modalElement = document.getElementById('tourViewModal');
  tourViewModal = new bootstrap.Modal(modalElement);
  modalElement.addEventListener('hidden.bs.modal', () => {
    tourViewer?.destroy();
    tourViewer = null;
  });
  document.getElementById('tourPlan').addEventListener('click', onTourPlanClick);
  // Ctrl + ลูกกลิ้งเมาส์ = ซูมที่ตำแหน่งเมาส์ (ไม่กด Ctrl = เลื่อนหน้าตามปกติ)
  document.getElementById('tourPlanViewport').addEventListener('wheel', (event) => {
    if (!event.ctrlKey) return;
    event.preventDefault();
    zoomTourPlan(event.deltaY < 0 ? 1 : -1, { clientX: event.clientX, clientY: event.clientY });
  }, { passive: false });
}

function tourPoint(id) {
  return tourState.points.find((point) => point.id === Number(id)) || null;
}

function tourFloor() {
  return document.getElementById('tourFloorSelect').value;
}

function tourPointName(point) {
  return point.label || (point.room_code ? `หน้าห้อง ${point.room_code}` : `จุด #${point.id}`);
}

async function loadTourPage() {
  try {
    await refreshBuildingList();
    fillSelect(document.getElementById('tourBuildingSelect'),
      buildings.map((building) => ({ value: building.id, label: `${building.name} (${building.code})` })));
    await loadTourBuilding();
  } catch (error) {
    reportError(error);
  }
}

async function loadTourBuilding({ keepFloor = false } = {}) {
  const buildingId = Number(document.getElementById('tourBuildingSelect').value);
  tourState.building = buildings.find((building) => Number(building.id) === buildingId) || null;
  const requestId = ++tourState.requestId;
  if (!tourState.building) {
    Object.assign(tourState, { floorPlans: [], points: [], rooms: [] });
    renderTour();
    return;
  }
  try {
    const [floorPlans, tour, rooms] = await Promise.all([
      api(`/api/admin/floorplans?building_id=${buildingId}`),
      api(`/api/admin/tour/points?building_id=${buildingId}`),
      api(`/api/building/${encodeURIComponent(tourState.building.name)}`),
    ]);
    if (requestId !== tourState.requestId) return;
    Object.assign(tourState, { floorPlans, points: tour.points, rooms });
  } catch (error) {
    if (requestId !== tourState.requestId) return;
    reportError(error);
  }

  const floors = [...new Set([...tourState.floorPlans.map((plan) => plan.floor), ...tourState.points.map((point) => point.floor)])]
    .sort(floorSort);
  const select = document.getElementById('tourFloorSelect');
  const previous = select.value;
  fillSelect(select, floors.map((floor) => ({ value: floor, label: `ชั้น ${floor}` })));
  if (keepFloor && floors.includes(previous)) select.value = previous;
  if (!tourPoint(tourState.selectedId)) tourState.selectedId = null;
  if (!tourPoint(tourState.placingId)) tourState.placingId = null;
  renderTour();
}

// ซูมแผนผังทีละขั้น คงจุดที่กำลังมองอยู่ (กึ่งกลางจอ หรือตำแหน่งเมาส์) ไว้ที่เดิม
const TOUR_ZOOM_STEPS = [1, 1.5, 2, 3, 4];

function applyTourZoom(zoom, anchor) {
  const viewport = document.getElementById('tourPlanViewport');
  const plan = document.getElementById('tourPlan');
  const rect = viewport.getBoundingClientRect();
  const ax = anchor ? anchor.clientX - rect.left : rect.width / 2;
  const ay = anchor ? anchor.clientY - rect.top : rect.height / 2;
  const fx = (viewport.scrollLeft + ax) / Math.max(plan.scrollWidth, 1);
  const fy = (viewport.scrollTop + ay) / Math.max(plan.scrollHeight, 1);
  tourState.zoom = zoom;
  plan.style.setProperty('--plan-zoom', zoom);
  document.getElementById('tourZoomLabel').textContent = `${Math.round(zoom * 100)}%`;
  viewport.scrollLeft = fx * plan.scrollWidth - ax;
  viewport.scrollTop = fy * plan.scrollHeight - ay;
}

function zoomTourPlan(direction, anchor) {
  const index = TOUR_ZOOM_STEPS.indexOf(tourState.zoom);
  const next = Math.min(TOUR_ZOOM_STEPS.length - 1, Math.max(0, Math.max(index, 0) + direction));
  applyTourZoom(TOUR_ZOOM_STEPS[next], anchor);
}

function resetTourZoom() {
  applyTourZoom(1);
  const viewport = document.getElementById('tourPlanViewport');
  viewport.scrollLeft = 0;
  viewport.scrollTop = 0;
}

function changeTourFloor() {
  resetTourZoom();
  tourState.placingId = null;
  const selected = tourPoint(tourState.selectedId);
  if (selected && selected.floor !== tourFloor()) tourState.selectedId = null;
  renderTour();
}

function renderTour() {
  const hasBuilding = Boolean(tourState.building);
  const floor = tourFloor();
  document.getElementById('tourUploadButton').disabled = !hasBuilding || !floor;
  document.getElementById('tourPreviewButton').disabled = !tourState.points.some((point) => point.x !== null);
  renderTourHint();
  renderTourPlan();
  renderTourUnplaced();
  renderTourDetail();
}

function renderTourHint() {
  const hint = document.getElementById('tourHint');
  hint.textContent = tourState.placingId ? '📍 คลิกบนแผนผังตรงตำแหน่งที่ถ่ายภาพนี้' : 'คลิกจุดเพื่อดูรายละเอียด';
}

function renderTourPlan() {
  const container = document.getElementById('tourPlan');
  const floor = tourFloor();
  const plan = tourState.floorPlans.find((item) => item.floor === floor);
  container.classList.toggle('is-placing', Boolean(tourState.placingId));

  if (!tourState.building || !floor) {
    container.innerHTML = '<div class="empty-state text-center">เลือกอาคารและชั้น (ต้องมีแผนผังชั้นก่อน ที่เมนู Floor Plans)</div>';
    return;
  }
  if (!plan) {
    container.innerHTML = `<div class="empty-state text-center">ชั้น ${escapeHtml(floor)} ยังไม่มีแผนผัง — เพิ่มที่เมนู Floor Plans ก่อนจึงจะวางจุดได้</div>`;
    return;
  }

  // กว้างตามสัดส่วนแผนผัง เพื่อให้แผนผังสูงเกินจอไม่ยืดยาว (ดู .tour-plan ใน index.html)
  const ratio = Number(plan.width) / Number(plan.height);
  if (Number.isFinite(ratio) && ratio > 0) container.style.setProperty('--plan-ratio', ratio);
  else container.style.removeProperty('--plan-ratio');

  const onFloor = tourState.points.filter((point) => point.floor === floor && point.x !== null);
  const dots = onFloor.map((point) => {
    const classes = ['tour-dot'];
    if (point.id === tourState.selectedId) classes.push('is-selected');
    return `<button type="button" class="${classes.join(' ')}" data-point-id="${point.id}"
      style="left:${point.x}%; top:${point.y}%;" title="${escapeHtml(tourPointName(point))}"></button>`;
  }).join('');

  container.innerHTML = `
    <img src="${escapeHtml(plan.image_url)}" alt="แผนผัง ชั้น ${escapeHtml(floor)}" draggable="false">
    ${dots}`;
}

function renderTourUnplaced() {
  const list = tourState.points.filter((point) => point.x === null);
  document.getElementById('tourUnplacedCount').textContent = list.length;
  const container = document.getElementById('tourUnplaced');
  if (list.length === 0) {
    container.innerHTML = '<div class="col-12 small text-secondary">ไม่มี — ภาพที่อัปโหลดใหม่จะมารออยู่ตรงนี้</div>';
    return;
  }
  container.innerHTML = list.map((point) => `
    <div class="col-6">
      <button type="button" class="tour-unplaced ${point.id === tourState.placingId ? 'is-selected' : ''}" onclick="startPlacing(${point.id})">
        <img class="tour-thumb" src="${escapeHtml(point.image_url)}" alt="" loading="lazy">
        <div class="small text-truncate mt-1">${escapeHtml(tourPointName(point))} · ชั้น ${escapeHtml(point.floor)}</div>
      </button>
    </div>`).join('');
}

function renderTourDetail() {
  const container = document.getElementById('tourDetail');
  const point = tourPoint(tourState.selectedId);
  if (!point) {
    container.innerHTML = '<p class="small text-secondary mb-0">คลิกจุดบนแผนผังเพื่อแก้ไขชื่อ ผูกห้อง ตั้งมุมเริ่มต้น หรือลบ</p>';
    return;
  }
  const roomOptions = [...tourState.rooms]
    .sort((a, b) => (a.floor === point.floor ? 0 : 1) - (b.floor === point.floor ? 0 : 1) || String(a.room_code).localeCompare(String(b.room_code), 'th'))
    .map((room) => `<option value="${room.id}" ${room.id === point.room_id ? 'selected' : ''}>${escapeHtml(room.room_code)} (ชั้น ${escapeHtml(room.floor || '-')})</option>`)
    .join('');
  const hasInitial = point.initial_yaw !== null && point.initial_yaw !== undefined;

  container.innerHTML = `
    <a href="${escapeHtml(point.image_url)}" target="_blank" rel="noopener"><img class="tour-thumb mb-2" style="height:110px" src="${escapeHtml(point.image_url)}" alt="ภาพ 360°"></a>
    <div class="small text-secondary mb-2">จุด #${point.id} · ชั้น ${escapeHtml(point.floor)}${hasInitial ? ' · ตั้งมุมเริ่มต้นแล้ว' : ''}</div>
    <label class="form-label small fw-semibold mb-1" for="tourPointLabel">ชื่อจุด (ผู้ใช้เห็นชื่อนี้)</label>
    <input id="tourPointLabel" class="form-control form-control-sm mb-2" maxlength="100" placeholder="เช่น โถงกลาง, หน้าลิฟต์" value="${escapeHtml(point.label || '')}">
    <label class="form-label small fw-semibold mb-1" for="tourPointRoom">ผูกกับห้อง (ปุ่ม "เดินชมจากหน้าห้องนี้" ในแอป)</label>
    <select id="tourPointRoom" class="form-select form-select-sm mb-2"><option value="">— ไม่ผูก —</option>${roomOptions}</select>
    <div class="d-flex flex-wrap gap-2 mb-1">
      <button type="button" class="btn btn-sm btn-primary" id="tourSavePoint" onclick="saveTourPoint(${point.id})">บันทึก</button>
      <button type="button" class="btn btn-sm btn-outline-primary" onclick="openTourViewer(${point.id})" ${point.x === null ? 'disabled title="วางจุดบนแผนผังก่อน"' : ''}>ตั้งมุมเริ่มต้น</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" onclick="startPlacing(${point.id})">ย้ายตำแหน่ง</button>
      <button type="button" class="btn btn-sm btn-outline-danger ms-auto" onclick="deleteTourPoint(${point.id})">ลบ</button>
    </div>`;
}

function startPlacing(id) {
  const point = tourPoint(id);
  if (!point) return;
  if (point.floor !== tourFloor()) {
    document.getElementById('tourFloorSelect').value = point.floor;
  }
  tourState.placingId = tourState.placingId === id ? null : id;
  tourState.selectedId = id;
  renderTour();
}

async function onTourPlanClick(event) {
  const dot = event.target.closest('.tour-dot');
  if (tourState.placingId) {
    if (dot && Number(dot.dataset.pointId) !== tourState.placingId) return;
    const image = document.querySelector('#tourPlan img');
    if (!image) return;
    const rect = image.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 100;
    const y = ((event.clientY - rect.top) / rect.height) * 100;
    if (x < 0 || x > 100 || y < 0 || y > 100) return;
    const id = tourState.placingId;
    tourState.placingId = null;
    await updateTourPoint(id, { x: Number(x.toFixed(3)), y: Number(y.toFixed(3)), floor: tourFloor() }, 'วางจุดแล้ว');
    return;
  }
  if (!dot) return;
  tourState.selectedId = Number(dot.dataset.pointId);
  renderTour();
}

function replaceTourPoint(point) {
  const index = tourState.points.findIndex((item) => item.id === point.id);
  if (index >= 0) tourState.points[index] = point;
  else tourState.points.push(point);
}

async function updateTourPoint(id, changes, message) {
  try {
    const data = await api(`/api/admin/tour/points/${id}`, jsonRequest('PUT', changes));
    replaceTourPoint(data.point);
    showStatus(message || data.message);
  } catch (error) {
    reportError(error);
  }
  renderTour();
}

async function saveTourPoint(id) {
  const button = document.getElementById('tourSavePoint');
  setBusy(button, true, 'กำลังบันทึก...', 'บันทึก');
  const roomValue = document.getElementById('tourPointRoom').value;
  await updateTourPoint(id, {
    label: document.getElementById('tourPointLabel').value,
    room_id: roomValue ? Number(roomValue) : null,
  });
}

async function deleteTourPoint(id) {
  const point = tourPoint(id);
  if (!point || !confirm(`ต้องการลบ "${tourPointName(point)}" ใช่หรือไม่?`)) return;
  try {
    await api(`/api/admin/tour/points/${id}`, { method: 'DELETE' });
    tourState.points = tourState.points.filter((item) => item.id !== id);
    tourState.selectedId = null;
    showStatus('ลบจุดแล้ว');
  } catch (error) {
    reportError(error);
  }
  renderTour();
}

async function uploadTourImages(input) {
  const files = [...input.files];
  input.value = '';
  if (files.length === 0 || !tourState.building) return;
  const floor = tourFloor();
  const button = document.getElementById('tourUploadButton');
  const failures = [];
  let firstNew = null;

  for (const [index, file] of files.entries()) {
    setBusy(button, true, `กำลังอัปโหลด ${index + 1}/${files.length}...`, '+ อัปโหลดภาพ 360°');
    const invalid = validateImageFile(file, TOUR_MAX_UPLOAD_MB);
    if (invalid) {
      failures.push(`${file.name}: ${invalid}`);
      continue;
    }
    const form = new FormData();
    form.append('building_id', tourState.building.id);
    form.append('floor', floor);
    form.append('label', file.name.replace(/\.[^.]+$/, '').slice(0, 100));
    form.append('image', file);
    try {
      const data = await api('/api/admin/tour/points', { method: 'POST', body: form });
      replaceTourPoint(data.point);
      firstNew = firstNew || data.point.id;
      renderTourUnplaced();
    } catch (error) {
      if (error instanceof SessionExpiredError) return;
      failures.push(`${file.name}: ${error.message}`);
    }
  }
  setBusy(button, false, '', '+ อัปโหลดภาพ 360°');
  if (failures.length > 0) {
    showStatus(`อัปโหลดไม่สำเร็จ ${failures.length} ไฟล์ — ${failures.join(' • ')}`, 'danger');
  } else {
    showStatus(`อัปโหลดแล้ว ${files.length} ภาพ — คลิกภาพในรายการ "ยังไม่วาง" แล้วคลิกบนแผนผัง`);
  }
  if (firstNew) startPlacing(firstNew);
  else renderTour();
}

function previewTour() {
  if (!tourState.building) return;
  const selected = tourPoint(tourState.selectedId);
  const query = new URLSearchParams({ building: tourState.building.id });
  if (selected && selected.x !== null) query.set('point', selected.id);
  window.open(`/tour/?${query}`, '_blank', 'noopener');
}

// ---------- มุมเริ่มต้นของจุด ----------
// มุมเริ่มต้น = มุมที่ผู้ใช้เห็นตอนเข้าเดินชมที่จุดนี้ ลากภาพไปมุมที่ต้องการแล้วกดตั้ง
async function openTourViewer(id) {
  const point = tourPoint(id);
  if (!point || point.x === null) return;
  tourViewModal.show();
  await mountTourViewer(id);
}

// restore = มุมที่กำลังมองอยู่ ใช้คืนมุมเดิมหลังบันทึกแล้วสร้างตัวดูใหม่ ภาพจึงไม่กระโดด
async function mountTourViewer(id, restore = null) {
  tourViewer?.destroy();
  tourViewer = null;
  const container = document.getElementById('tourViewer');
  container.innerHTML = '';
  try {
    const [{ createTourViewer, prepareTour }, data] = await Promise.all([
      import('./tour.js'),
      api(`/api/tour/${tourState.building.id}`),
    ]);
    const holder = document.createElement('div');
    holder.style.cssText = 'position:absolute; inset:0;';
    container.appendChild(holder);
    let restored = false;
    tourViewer = createTourViewer(holder, prepareTour(data), {
      startPointId: id,
      mapSize: '150px',
      useInitialView: !restore,
      onNodeChange: () => {
        if (restore && !restored) {
          restored = true;
          tourViewer?.viewer.rotate({ yaw: restore.yaw, pitch: restore.pitch });
        }
        renderTourViewPanel();
      },
    });
  } catch (error) {
    reportError(error);
  }
}

function renderTourViewPanel() {
  const current = tourViewer?.currentPoint;
  if (!current) return;
  const point = tourPoint(current.id) || current;
  const hasInitial = point.initial_yaw !== null && point.initial_yaw !== undefined;
  document.getElementById('tourViewModalTitle').textContent = `ตั้งมุมเริ่มต้น: ${tourPointName(point)}`;
  document.getElementById('tourInitialClear').disabled = !hasInitial;
  document.getElementById('tourInitialState').textContent = hasInitial
    ? 'ตั้งมุมเริ่มต้นไว้แล้ว — ผู้ใช้จะเห็นภาพหันไปทางนี้ตอนเข้าดูจุดนี้'
    : 'ยังไม่ได้ตั้งมุมเริ่มต้น (เริ่มที่กลางภาพ)';
}

async function saveTourInitialView(pointId, body) {
  const view = tourViewer?.viewer.getPosition();
  const restore = view ? { yaw: view.yaw, pitch: view.pitch } : null;
  try {
    const data = await api(`/api/admin/tour/points/${pointId}/initial-view`, jsonRequest('PUT', body));
    replaceTourPoint(data.point);
    renderTour();
    showStatus(data.message);
    await mountTourViewer(pointId, restore);
  } catch (error) {
    reportError(error);
  }
}

async function setTourInitialView() {
  const point = tourViewer?.currentPoint;
  if (!point) return;
  const view = tourViewer.viewer.getPosition();
  const yaw = Math.atan2(Math.sin(view.yaw), Math.cos(view.yaw));
  await saveTourInitialView(point.id, { yaw, pitch: view.pitch });
}

async function clearTourInitialView() {
  const point = tourViewer?.currentPoint;
  if (point) await saveTourInitialView(point.id, { yaw: null, pitch: null });
}
