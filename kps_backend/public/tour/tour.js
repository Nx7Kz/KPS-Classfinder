// หน้าเดินชมอาคาร (ใช้ร่วมกันระหว่างหน้า /tour/ ในแอป และหน้าดูตัวอย่างในแดชบอร์ด)
// ข้อมูลมาจาก GET /api/tour/:buildingId — จุดถ่ายวางบนแผนผังเป็น % ผู้ใช้เลือกจุดที่จะดูจาก "แผนที่ย่อ" มุมจอ
// (แตะจุดสีเขียวเพื่อไปดูภาพนั้น) ไม่มีการเดินต่อเนื่อง ไม่ใช้ทิศของภาพ และไม่มีป้ายห้องลอยในภาพ
import { Viewer, SYSTEM } from '@photo-sphere-viewer/core';
import { VirtualTourPlugin } from '@photo-sphere-viewer/virtual-tour-plugin';

// จอมือถือความละเอียดสูง (devicePixelRatio 3 ขึ้นไป) ทำให้ WebGL ต้องเรนเดอร์ทุกพิกเซลจริงของจอ
// บวก MSAA เต็มรูปแบบ บนมือถือจำลอง/เครื่องเก่าจะกระตุกมาก จึงจำกัดไว้ไม่เกิน 2 และปิด MSAA
SYSTEM.load();
SYSTEM.pixelRatio = Math.min(SYSTEM.pixelRatio, 2);

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

export function prepareTour(data) {
  const floors = new Map(data.floors.map((floor) => [floor.floor, floor]));
  const points = new Map(data.points.map((point) => [point.id, point]));
  const pixel = (point) => {
    const plan = floors.get(point.floor);
    const width = plan?.width || 1000;
    const height = plan?.height || 1000;
    return { x: point.x / 100 * width, y: point.y / 100 * height, width, height };
  };
  const tourFloors = [...new Set(data.points.map((point) => point.floor))]
    .sort((a, b) => a.localeCompare(b, 'th', { numeric: true }));
  return { ...data, floorMap: floors, pointMap: points, pixel, tourFloors };
}

function pointName(point) {
  return point.label || (point.room_code ? `หน้าห้อง ${point.room_code}` : `จุดที่ ${point.id}`);
}


// ---------- แผนที่ย่อ (เขียนเอง) ----------
// แสดงแผนผังทั้งชั้นนิ่ง ๆ ไม่เลื่อนตามจุดที่ยืนอยู่ (ต่างจากแผนที่ของปลั๊กอินที่เลื่อนตามเสมอ) แตะจุดเพื่อไปดูภาพนั้น
// จุดสีฟ้า = จุดที่ดูอยู่ จุดสีเขียว = จุดอื่นในชั้นเดียวกัน ปุ่มมุมขวาบนสลับขนาดเล็ก/ใหญ่
const MINIMAP_CSS = `
.kps-minimap { position: absolute; left: 12px; bottom: calc(12px + var(--kps-safe-bottom, 0px)); z-index: 30;
  width: var(--mini-size, 190px); height: var(--mini-size, 190px); max-width: 90vw; max-height: 70vh; box-sizing: border-box;
  background: #fff; border: 2px solid #fff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 16px rgba(0,0,0,.35);
  transition: width .2s ease, height .2s ease; touch-action: manipulation; }
.kps-minimap.is-big { width: min(86vw, 62vh); height: min(86vw, 62vh); }
.kps-minimap-stage { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: #f8faf9; }
.kps-minimap-plan { position: relative; flex: none; }
.kps-minimap-plan img { display: block; width: 100%; height: 100%; pointer-events: none; user-select: none; -webkit-user-drag: none; }
.kps-minimap-dot { position: absolute; width: 22px; height: 22px; margin: -11px 0 0 -11px; padding: 0; border: 0; background: transparent; cursor: pointer; -webkit-tap-highlight-color: transparent; }
.kps-minimap-dot::before { content: ''; position: absolute; left: 50%; top: 50%; width: 14px; height: 14px; margin: -7px 0 0 -7px;
  border-radius: 50%; background: #15803d; border: 2px solid #fff; box-shadow: 0 0 0 1px rgba(0,0,0,.3); transition: transform .12s ease; }
.kps-minimap-dot:hover::before { transform: scale(1.25); }
.kps-minimap-dot.is-current { z-index: 2; cursor: default; }
.kps-minimap-dot.is-current::before { width: 18px; height: 18px; margin: -9px 0 0 -9px; background: #2563eb; box-shadow: 0 0 0 5px rgba(37,99,235,.28); }
.kps-minimap-toggle { position: absolute; top: 6px; right: 6px; z-index: 3; width: 32px; height: 32px; border: 0; border-radius: 9px;
  background: rgba(0,0,0,.55); color: #fff; font-size: 17px; line-height: 1; cursor: pointer; }
`;

function createMinimap(container, tour, { size, onSelect }) {
  if (!document.getElementById('kps-minimap-style')) {
    const style = document.createElement('style');
    style.id = 'kps-minimap-style';
    style.textContent = MINIMAP_CSS;
    document.head.appendChild(style);
  }
  const root = document.createElement('div');
  root.className = 'kps-minimap';
  root.style.setProperty('--mini-size', size);
  root.innerHTML = `<div class="kps-minimap-stage"><div class="kps-minimap-plan"><img alt="แผนผังชั้น" draggable="false"></div></div>
    <button type="button" class="kps-minimap-toggle" aria-label="ขยายหรือย่อแผนที่">⤢</button>`;
  // ไม่ให้การแตะ/ลากบนแผนที่ไปหมุนภาพ 360° ข้างหลัง
  for (const type of ['pointerdown', 'mousedown', 'touchstart', 'click', 'wheel', 'dblclick']) {
    root.addEventListener(type, (event) => event.stopPropagation());
  }
  const stage = root.querySelector('.kps-minimap-stage');
  const planBox = root.querySelector('.kps-minimap-plan');
  const image = planBox.querySelector('img');
  let floor = null;
  let currentId = null;

  function layout() {
    const plan = tour.floorMap.get(floor);
    if (!plan || !stage.clientWidth) return;
    const scale = Math.min(stage.clientWidth / plan.width, stage.clientHeight / plan.height);
    planBox.style.width = `${plan.width * scale}px`;
    planBox.style.height = `${plan.height * scale}px`;
  }

  function buildDots() {
    planBox.querySelectorAll('.kps-minimap-dot').forEach((dot) => dot.remove());
    for (const point of tour.points.filter((item) => item.floor === floor)) {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = 'kps-minimap-dot';
      dot.dataset.pointId = String(point.id);
      dot.style.left = `${point.x}%`;
      dot.style.top = `${point.y}%`;
      dot.title = pointName(point);
      dot.setAttribute('aria-label', pointName(point));
      dot.addEventListener('click', () => {
        if (point.id !== currentId) onSelect(point.id);
      });
      planBox.appendChild(dot);
    }
  }

  root.querySelector('.kps-minimap-toggle').addEventListener('click', () => {
    root.classList.toggle('is-big');
    setTimeout(layout, 230);
  });
  if (typeof ResizeObserver === 'function') new ResizeObserver(layout).observe(stage);

  container.appendChild(root);
  return {
    show(point) {
      currentId = point.id;
      if (point.floor !== floor) {
        floor = point.floor;
        const plan = tour.floorMap.get(floor);
        if (plan) image.src = plan.image;
        layout();
        buildDots();
      }
      planBox.querySelectorAll('.kps-minimap-dot').forEach((dot) => {
        dot.classList.toggle('is-current', Number(dot.dataset.pointId) === point.id);
      });
    },
    destroy() {
      root.remove();
    },
  };
}

// ไม่มีลิงก์ระหว่างจุด (ปลั๊กอินจะวาดลูกศรบนพื้นให้ทุกลิงก์) ผู้ใช้เลือกจุดจากแผนที่ย่อ
function buildNode(tour, point) {
  return {
    id: String(point.id),
    panorama: point.image_url,
    name: pointName(point),
    links: [],
    data: { point },
  };
}

/**
 * สร้างหน้าเดินชมใน container
 * options: startPointId, onNodeChange(point), mapSize, useInitialView (ค่าเริ่มต้น true = เปิดจุดแรกที่มุมเริ่มต้นที่ตั้งไว้)
 */
export function createTourViewer(container, tour, options = {}) {
  const startPoint = tour.pointMap.get(options.startPointId) || tour.points[0];

  const viewer = new Viewer({
    container,
    loadingTxt: 'กำลังโหลดภาพ…',
    navbar: false,
    defaultZoomLvl: 20,
    mousewheelCtrlKey: false,
    touchmoveTwoFingers: false,
    lang: { loadError: 'โหลดภาพไม่สำเร็จ', twoFingers: 'ใช้สองนิ้วเพื่อเลื่อน' },
    // ปิด MSAA: มุมมองทรงกลมมองจากศูนย์กลางมีขอบคมอยู่แค่รอยต่อภาพ (ทำ anti-alias ใน shader แล้ว)
    rendererParameters: { antialias: false, powerPreference: 'high-performance' },
    plugins: [
      VirtualTourPlugin.withConfig({
        positionMode: 'manual',
        renderMode: '3d',
        preload: false,
        startNodeId: String(startPoint.id),
        nodes: tour.points.map((point) => buildNode(tour, point)),
        showLinkTooltip: false,
        transitionOptions: { showLoader: false, effect: 'fade', speed: 700, rotation: false },
      }),
    ],
  });

  const plugin = viewer.getPlugin(VirtualTourPlugin);
  const minimap = createMinimap(container, tour, {
    size: options.mapSize || '150px',
    onSelect: (pointId) => plugin.setCurrentNode(String(pointId)),
  });

  // มุมเริ่มต้น: ใช้เฉพาะตอนเข้าเดินชมที่จุดแรก (ตอนไปจุดอื่นเริ่มที่มุมที่กำลังมองอยู่)
  let startViewApplied = false;
  plugin.addEventListener('node-changed', ({ node }) => {
    const point = node.data.point;
    minimap.show(point);
    if (!startViewApplied) {
      startViewApplied = true;
      if (options.useInitialView !== false && point.initial_yaw != null && point.initial_pitch != null) {
        viewer.rotate({ yaw: point.initial_yaw, pitch: point.initial_pitch });
      }
    }
    options.onNodeChange?.(point);
  });

  return {
    viewer,
    plugin,
    get currentPoint() {
      return plugin.getCurrentNode()?.data.point;
    },
    goTo(pointId) {
      return plugin.setCurrentNode(String(pointId));
    },
    /** จุดในชั้นที่เลือกที่ใกล้ตำแหน่งปัจจุบันที่สุด (ใช้กับปุ่มเปลี่ยนชั้น) */
    nearestOnFloor(floor) {
      const current = this.currentPoint;
      return tour.points
        .filter((point) => point.floor === floor)
        .map((point) => ({ point, distance: Math.hypot(point.x - current.x, point.y - current.y) }))
        .sort((a, b) => a.distance - b.distance)[0]?.point;
    },
    destroy() {
      minimap.destroy();
      viewer.destroy();
    },
  };
}
