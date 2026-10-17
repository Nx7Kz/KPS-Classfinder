// ============ หน้า Virtual Tour (เดินชมอาคาร 360°) ในแดชบอร์ด ============
// ใช้ helper กลางจาก index.html: api, jsonRequest, reportError, showStatus, setBusy, escapeHtml,
// refreshBuildingList, fillSelect, floorSort, validateImageFile, buildings
/* global api, jsonRequest, reportError, showStatus, setBusy, escapeHtml, refreshBuildingList, fillSelect,
   floorSort, validateImageFile, buildings, bootstrap, SessionExpiredError */

const TOUR_MAX_UPLOAD_MB = 40;

const tourState = {
  building: null,
  floorPlans: [],
  points: [],
  links: [],
  rooms: [],
  mode: 'select', // 'select' | 'link'
  selectedId: null,
  placingId: null, // จุดที่กำลังรอคลิกวางบนแผนผัง
  linkFromId: null,
  requestId: 0,
};
let tourHeadingModal;
let tourHeadingViewer = null;

function initTourPage() {
  const modalElement = document.getElementById('tourHeadingModal');
  tourHeadingModal = new bootstrap.Modal(modalElement);
  modalElement.addEventListener('hidden.bs.modal', () => {
    tourHeadingViewer?.destroy();
    tourHeadingViewer = null;
  });
  document.getElementById('tourPlan').addEventListener('click', onTourPlanClick);
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

function tourNeighbors(id) {
  return tourState.links
    .filter(([a, b]) => a === id || b === id)
    .map(([a, b]) => (a === id ? b : a));
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
    Object.assign(tourState, { floorPlans: [], points: [], links: [], rooms: [] });
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
    Object.assign(tourState, { floorPlans, points: tour.points, links: tour.links, rooms });
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

function changeTourFloor() {
  tourState.placingId = null;
  tourState.linkFromId = null;
  const selected = tourPoint(tourState.selectedId);
  if (selected && selected.floor !== tourFloor()) tourState.selectedId = null;
  renderTour();
}

function setTourMode(mode) {
  tourState.mode = mode;
  tourState.linkFromId = null;
  tourState.placingId = null;
  renderTour();
}

function renderTour() {
  const hasBuilding = Boolean(tourState.building);
  const floor = tourFloor();
  document.getElementById('tourUploadButton').disabled = !hasBuilding || !floor;
  document.getElementById('tourAutoLinkButton').disabled = !hasBuilding || !floor;
  document.getElementById('tourPreviewButton').disabled = !tourState.points.some((point) => point.x !== null);
  renderTourHint();
  renderTourPlan();
  renderTourUnplaced();
  renderTourDetail();
}

function renderTourHint() {
  const hint = document.getElementById('tourHint');
  if (tourState.placingId) hint.textContent = '📍 คลิกบนแผนผังตรงตำแหน่งที่ถ่ายภาพนี้';
  else if (tourState.mode === 'link' && tourState.linkFromId) hint.textContent = 'คลิกจุดที่สองเพื่อเชื่อม (ถ้าเชื่อมอยู่แล้วจะเป็นการตัดเส้น)';
  else if (tourState.mode === 'link') hint.textContent = 'คลิกจุดแรกของเส้นที่ต้องการเชื่อมหรือตัด';
  else hint.textContent = 'คลิกจุดเพื่อดูรายละเอียด';
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

  const onFloor = tourState.points.filter((point) => point.floor === floor && point.x !== null);
  const ids = new Set(onFloor.map((point) => point.id));
  // เส้นในชั้นเดียวกัน (ใช้ viewBox 0-100 ตรงกับ % ของตำแหน่ง)
  const lines = tourState.links
    .filter(([a, b]) => ids.has(a) && ids.has(b))
    .map(([a, b]) => {
      const p = tourPoint(a);
      const q = tourPoint(b);
      return `<line x1="${p.x}" y1="${p.y}" x2="${q.x}" y2="${q.y}" stroke="#15803d" stroke-width="3"
        stroke-linecap="round" vector-effect="non-scaling-stroke" opacity=".85"/>`;
    }).join('');
  const dots = onFloor.map((point) => {
    const stairs = tourNeighbors(point.id).some((id) => tourPoint(id)?.floor !== floor);
    const classes = ['tour-dot'];
    if (point.id === tourState.selectedId) classes.push('is-selected');
    if (point.id === tourState.linkFromId) classes.push('is-link-from');
    if (stairs) classes.push('has-stairs');
    return `<button type="button" class="${classes.join(' ')}" data-point-id="${point.id}"
      style="left:${point.x}%; top:${point.y}%;" title="${escapeHtml(tourPointName(point))}"></button>`;
  }).join('');

  container.innerHTML = `
    <img src="${escapeHtml(plan.image_url)}" alt="แผนผัง ชั้น ${escapeHtml(floor)}" draggable="false">
    <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">${lines}</svg>
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
    container.innerHTML = '<p class="small text-secondary mb-0">คลิกจุดบนแผนผังเพื่อแก้ไขชื่อ ผูกห้อง ตั้งทิศ หรือลบ</p>';
    return;
  }
  const neighbors = tourNeighbors(point.id).map(tourPoint).filter(Boolean);
  const otherFloorPoints = tourState.points.filter((other) => other.floor !== point.floor && other.x !== null);
  const roomOptions = [...tourState.rooms]
    .sort((a, b) => (a.floor === point.floor ? 0 : 1) - (b.floor === point.floor ? 0 : 1) || String(a.room_code).localeCompare(String(b.room_code), 'th'))
    .map((room) => `<option value="${room.id}" ${room.id === point.room_id ? 'selected' : ''}>${escapeHtml(room.room_code)} (ชั้น ${escapeHtml(room.floor || '-')})</option>`)
    .join('');

  container.innerHTML = `
    <a href="${escapeHtml(point.image_url)}" target="_blank" rel="noopener"><img class="tour-thumb mb-2" style="height:110px" src="${escapeHtml(point.image_url)}" alt="ภาพ 360°"></a>
    <div class="small text-secondary mb-2">จุด #${point.id} · ชั้น ${escapeHtml(point.floor)} · ทิศ ${Number(point.heading).toFixed(1)}°</div>
    <label class="form-label small fw-semibold mb-1" for="tourPointLabel">ชื่อจุด</label>
    <input id="tourPointLabel" class="form-control form-control-sm mb-2" maxlength="100" placeholder="เช่น ทางเดินหน้าห้อง 207" value="${escapeHtml(point.label || '')}">
    <label class="form-label small fw-semibold mb-1" for="tourPointRoom">ผูกกับห้อง (ปุ่ม "เดินชมจากหน้าห้องนี้" ในแอป)</label>
    <select id="tourPointRoom" class="form-select form-select-sm mb-2"><option value="">— ไม่ผูก —</option>${roomOptions}</select>
    <div class="d-flex flex-wrap gap-2 mb-3">
      <button type="button" class="btn btn-sm btn-primary" id="tourSavePoint" onclick="saveTourPoint(${point.id})">บันทึก</button>
      <button type="button" class="btn btn-sm btn-outline-primary" onclick="openTourHeading(${point.id})" ${point.x === null || neighbors.length === 0 ? 'disabled title="วางจุดและเชื่อมกับจุดอื่นก่อน"' : ''}>ตั้งทิศ</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" onclick="startPlacing(${point.id})">ย้ายตำแหน่ง</button>
      <button type="button" class="btn btn-sm btn-outline-danger ms-auto" onclick="deleteTourPoint(${point.id})">ลบ</button>
    </div>
    <div class="small fw-semibold mb-1">เชื่อมกับ (${neighbors.length})</div>
    <ul class="list-group list-group-flush small mb-3">
      ${neighbors.map((other) => `
        <li class="list-group-item px-0 d-flex align-items-center gap-2">
          <span class="text-truncate">${escapeHtml(tourPointName(other))}${other.floor !== point.floor ? ` <span class="badge text-bg-warning">ชั้น ${escapeHtml(other.floor)}</span>` : ''}</span>
          <button type="button" class="btn btn-sm btn-link text-danger ms-auto p-0" onclick="toggleTourLink(${point.id}, ${other.id})" aria-label="ตัดเส้น">ตัด</button>
        </li>`).join('') || '<li class="list-group-item px-0 text-secondary">ยังไม่ได้เชื่อม</li>'}
    </ul>
    ${otherFloorPoints.length > 0 ? `
      <label class="form-label small fw-semibold mb-1" for="tourStairsTarget">เชื่อมข้ามชั้น (บันได / ลิฟต์)</label>
      <div class="input-group input-group-sm">
        <select id="tourStairsTarget" class="form-select">
          ${otherFloorPoints.map((other) => `<option value="${other.id}">ชั้น ${escapeHtml(other.floor)} · ${escapeHtml(tourPointName(other))}</option>`).join('')}
        </select>
        <button type="button" class="btn btn-outline-primary" onclick="linkTourStairs(${point.id})">เชื่อม</button>
      </div>` : ''}`;
}

function startPlacing(id) {
  const point = tourPoint(id);
  if (!point) return;
  if (point.floor !== tourFloor()) {
    document.getElementById('tourFloorSelect').value = point.floor;
  }
  tourState.mode = 'select';
  document.getElementById('tourModeSelect').checked = true;
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
  const id = Number(dot.dataset.pointId);
  if (tourState.mode === 'link') {
    if (!tourState.linkFromId) {
      tourState.linkFromId = id;
      renderTour();
    } else if (tourState.linkFromId === id) {
      tourState.linkFromId = null;
      renderTour();
    } else {
      const from = tourState.linkFromId;
      tourState.linkFromId = null;
      await toggleTourLink(from, id);
    }
    return;
  }
  tourState.selectedId = id;
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
  if (!point || !confirm(`ต้องการลบ "${tourPointName(point)}" และเส้นเชื่อมทั้งหมดของจุดนี้ใช่หรือไม่?`)) return;
  try {
    await api(`/api/admin/tour/points/${id}`, { method: 'DELETE' });
    tourState.points = tourState.points.filter((item) => item.id !== id);
    tourState.links = tourState.links.filter(([a, b]) => a !== id && b !== id);
    tourState.selectedId = null;
    showStatus('ลบจุดแล้ว');
  } catch (error) {
    reportError(error);
  }
  renderTour();
}

async function toggleTourLink(a, b) {
  const [pointA, pointB] = [Math.min(a, b), Math.max(a, b)];
  const exists = tourState.links.some(([x, y]) => x === pointA && y === pointB);
  try {
    await api('/api/admin/tour/links', jsonRequest(exists ? 'DELETE' : 'POST', { point_a: pointA, point_b: pointB }));
    tourState.links = exists
      ? tourState.links.filter(([x, y]) => !(x === pointA && y === pointB))
      : [...tourState.links, [pointA, pointB]];
    showStatus(exists ? 'ตัดเส้นแล้ว' : 'เชื่อมจุดแล้ว');
  } catch (error) {
    reportError(error);
  }
  renderTour();
}

async function linkTourStairs(id) {
  const target = Number(document.getElementById('tourStairsTarget').value);
  if (!target) return;
  if (tourNeighbors(id).includes(target)) {
    showStatus('สองจุดนี้เชื่อมกันอยู่แล้ว', 'warning');
    return;
  }
  await toggleTourLink(id, target);
}

async function autoLinkTour() {
  const button = document.getElementById('tourAutoLinkButton');
  setBusy(button, true, 'กำลังเชื่อม...', 'เชื่อมอัตโนมัติ');
  try {
    const data = await api('/api/admin/tour/autolink', jsonRequest('POST', {
      building_id: tourState.building.id, floor: tourFloor(),
    }));
    showStatus(data.added > 0 ? `${data.message} — ตรวจดูแล้วตัดเส้นที่ทะลุผนังออก` : 'ไม่มีเส้นใหม่ให้เชื่อม', data.added > 0 ? 'success' : 'warning');
    await loadTourBuilding({ keepFloor: true });
  } catch (error) {
    reportError(error);
  } finally {
    setBusy(button, false, '', 'เชื่อมอัตโนมัติ');
  }
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

// ---------- ตั้งทิศ ----------
// ตัวเลือก "หันไปทางจุด": จุดที่เชื่อมอยู่ก่อน ตามด้วยจุดอื่นในชั้นเดียวกัน
function fillTourHeadingTargets(id) {
  const point = tourPoint(id);
  if (!point) return false;
  const neighbors = tourNeighbors(id).map(tourPoint).filter((other) => other && other.x !== null);
  const sameFloor = tourState.points.filter((other) => other.id !== id && other.floor === point.floor && other.x !== null && !neighbors.includes(other));
  const options = [...neighbors.filter((other) => other.floor === point.floor), ...sameFloor];
  if (options.length === 0) return false;
  document.getElementById('tourHeadingModalTitle').textContent = `ตั้งทิศ: ${tourPointName(point)}`;
  fillSelect(document.getElementById('tourHeadingTarget'),
    options.map((other) => ({ value: other.id, label: `${tourPointName(other)}${neighbors.includes(other) ? ' (เชื่อมอยู่)' : ''}` })));
  document.getElementById('tourHeadingTarget').value = String(options[0].id);
  document.getElementById('tourHeadingInfo').textContent = `ทิศปัจจุบัน ${Number(point.heading).toFixed(1)}°`;
  return true;
}

async function openTourHeading(id) {
  if (!fillTourHeadingTargets(id)) {
    showStatus('ต้องมีจุดอื่นในชั้นเดียวกันเพื่อใช้อ้างอิงทิศ', 'warning');
    return;
  }
  tourHeadingModal.show();
  await mountTourHeadingViewer(id);
}

async function mountTourHeadingViewer(id) {
  tourHeadingViewer?.destroy();
  tourHeadingViewer = null;
  const container = document.getElementById('tourHeadingView');
  container.querySelectorAll('.psv-container').forEach((element) => element.remove());
  try {
    const [{ createTourViewer, prepareTour }, data] = await Promise.all([
      import('/tour/tour.js'),
      api(`/api/tour/${tourState.building.id}`),
    ]);
    const holder = document.createElement('div');
    holder.style.cssText = 'position:absolute; inset:0;';
    container.appendChild(holder);
    // เดินไปจุดอื่นในหน้านี้ได้ (ตั้งทิศทีละจุดต่อกันได้เลย) ตัวเลือกจะเปลี่ยนตามจุดที่ยืนอยู่
    tourHeadingViewer = createTourViewer(holder, prepareTour(data), {
      startPointId: id,
      mapSize: '140px',
      onNodeChange: (point) => fillTourHeadingTargets(point.id),
    });
  } catch (error) {
    reportError(error);
  }
}

async function saveTourHeading() {
  if (!tourHeadingViewer?.currentPoint) return;
  const point = tourHeadingViewer.currentPoint;
  const target = Number(document.getElementById('tourHeadingTarget').value);
  const heading = tourHeadingViewer.headingFacing(target);
  const button = document.getElementById('tourHeadingSave');
  setBusy(button, true, 'กำลังบันทึก...', 'ตั้งทิศ');
  try {
    const data = await api(`/api/admin/tour/points/${point.id}`, jsonRequest('PUT', { heading }));
    replaceTourPoint(data.point);
    renderTour();
    showStatus(`บันทึกทิศ ${heading.toFixed(1)}° แล้ว — ตรวจดูว่าลูกศรชี้ตรงทางเดินหรือไม่ ถ้ายังไม่ตรงหมุนแล้วกดตั้งทิศอีกครั้ง`);
    await mountTourHeadingViewer(point.id);
  } catch (error) {
    reportError(error);
  } finally {
    setBusy(button, false, '', 'ตั้งทิศ');
  }
}
