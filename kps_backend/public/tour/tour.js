// หน้าเดินชมอาคารแบบ Street View (ใช้ร่วมกันระหว่างหน้า /tour/ ในแอป และหน้าดูตัวอย่างในแดชบอร์ด)
// ข้อมูลมาจาก GET /api/tour/:buildingId — จุดถ่ายวางบนแผนผังเป็น % และ heading คือมุม (องศา) ในภาพต้นฉบับ
// ที่หันไปทาง "ขึ้น" ของแผนผัง (กึ่งกลางภาพ = 0) หมุนภาพด้วย sphereCorrection แล้ว yaw ของ viewer = ทิศบนแผนผัง
// ทุกภาพจึงใช้ทิศเดียวกัน: yaw ของลูกศร = ทิศจากจุดนี้ไปอีกจุดบนแผนผัง (yaw ที่จอ = yaw ในภาพ - heading)
import { Viewer, SYSTEM } from '@photo-sphere-viewer/core';
import { VirtualTourPlugin } from '@photo-sphere-viewer/virtual-tour-plugin';
import { MapPlugin } from '@photo-sphere-viewer/map-plugin';
import { MarkersPlugin } from '@photo-sphere-viewer/markers-plugin';

// จอมือถือความละเอียดสูง (devicePixelRatio 3 ขึ้นไป) ทำให้ WebGL ต้องเรนเดอร์ทุกพิกเซลจริงของจอ
// บวก MSAA เต็มรูปแบบ บนมือถือจำลอง/เครื่องเก่าจะกระตุกมาก จึงจำกัดไว้ไม่เกิน 2 (ของจริงแยกแยะไม่ออก
// บนจอมือถือที่ถืออยู่ไกลสายตา) และปิด MSAA — shader ของทรงกลมทำ anti-alias เฉพาะขอบภาพอยู่แล้ว
SYSTEM.load();
SYSTEM.pixelRatio = Math.min(SYSTEM.pixelRatio, 2);

const MAP_LINK_PREFIX = '__tour-link__'; // id ที่ VirtualTourPlugin ใช้กับจุดบนแผนที่ (คลิกแล้วเดินไปจุดนั้นให้เอง)
const ROOM_LABEL_RADIUS = 0.3; // แสดงป้ายห้องที่อยู่ห่างไม่เกิน 30% ของด้านกว้างแผนผัง
const ROOM_LABEL_MAX = 6;
const TAP_WALK_MAX_ANGLE = 0.6; // แตะพื้นห่างจากทิศของเส้นเชื่อมไม่เกิน ~35° ถึงจะเดินไป

const deg = (rad) => rad * 180 / Math.PI;
const rad = (degree) => degree * Math.PI / 180;

/** มุม -π..π */
export function wrapAngle(angle) {
  return Math.atan2(Math.sin(angle), Math.cos(angle));
}

export function shortRoomCode(code, buildingCode) {
  const prefix = `${buildingCode}-`;
  return code.startsWith(prefix) ? code.slice(prefix.length) : code;
}

export function prepareTour(data) {
  const floors = new Map(data.floors.map((floor) => [floor.floor, floor]));
  const points = new Map(data.points.map((point) => [point.id, point]));
  const neighbors = new Map(data.points.map((point) => [point.id, []]));
  for (const [a, b] of data.links) {
    if (!points.has(a) || !points.has(b)) continue;
    neighbors.get(a).push(b);
    neighbors.get(b).push(a);
  }
  const pixel = (point) => {
    const plan = floors.get(point.floor);
    const width = plan?.width || 1000;
    const height = plan?.height || 1000;
    return { x: point.x / 100 * width, y: point.y / 100 * height, width, height };
  };
  // ทิศบนแผนผัง (เรเดียน ตามเข็มนาฬิกาจากด้านบนของภาพแผนผัง)
  const bearing = (from, to) => {
    const a = pixel(from);
    const b = pixel(to);
    if (Math.hypot(b.x - a.x, b.y - a.y) < 1) return 0;
    return Math.atan2(b.x - a.x, a.y - b.y);
  };
  const tourFloors = [...new Set(data.points.map((point) => point.floor))]
    .sort((a, b) => a.localeCompare(b, 'th', { numeric: true }));
  return { ...data, floorMap: floors, pointMap: points, neighbors, pixel, bearing, tourFloors };
}

function pointName(point) {
  return point.label || (point.room_code ? `หน้าห้อง ${point.room_code}` : `จุดที่ ${point.id}`);
}

function linkName(tour, from, to) {
  if (to.floor !== from.floor) {
    const up = to.floor.localeCompare(from.floor, 'th', { numeric: true }) > 0;
    return `${up ? 'ขึ้น' : 'ลง'}ชั้น ${to.floor}`;
  }
  return pointName(to);
}

function roomTagHtml(tour, room) {
  return `<button class="kps-room-tag${room.status === 'maintenance' ? ' is-maintenance' : ''}" type="button">${
    escapeHtml(shortRoomCode(room.room_code, tour.building.code))}</button>`;
}

// ป้ายที่ผู้ดูแลตั้งตำแหน่งเองในภาพของจุดนี้ (yaw เก็บในพิกัดภาพต้นฉบับ จึงลบ heading ออกให้ตรงกับพิกัดบนจอ)
// ห้องที่มีการตั้งไว้ (ซ่อนหรือย้าย) จะไม่ถูกคำนวณอัตโนมัติซ้ำ
function manualRoomMarkers(tour, point, labels) {
  const rooms = new Map(tour.rooms.map((room) => [room.id, room]));
  return labels
    .filter((label) => !label.hidden && label.yaw !== null && rooms.has(label.room_id))
    .map((label) => {
      const room = rooms.get(label.room_id);
      return {
        id: `room-${room.id}`,
        position: { yaw: wrapAngle(label.yaw - rad(point.heading || 0)), pitch: label.pitch },
        html: roomTagHtml(tour, room),
        anchor: 'bottom center',
        data: { roomId: room.id, roomCode: room.room_code, manual: true },
      };
    });
}

function roomMarkers(tour, point) {
  const here = tour.pixel(point);
  const labels = (tour.labels || []).filter((label) => label.point_id === point.id);
  const overridden = new Set(labels.map((label) => label.room_id));
  return [...manualRoomMarkers(tour, point, labels), ...autoRoomMarkers(tour, point, here, overridden)];
}

function autoRoomMarkers(tour, point, here, overridden) {
  return tour.rooms
    .filter((room) => room.floor === point.floor && room.pin_x !== null && room.pin_y !== null && !overridden.has(room.id))
    .map((room) => {
      const target = { x: room.pin_x / 100 * here.width, y: room.pin_y / 100 * here.height };
      const distance = Math.hypot(target.x - here.x, target.y - here.y);
      return { room, distance, yaw: Math.atan2(target.x - here.x, here.y - target.y) };
    })
    .filter((item) => item.distance <= ROOM_LABEL_RADIUS * here.width)
    .sort((a, b) => a.distance - b.distance)
    .slice(0, ROOM_LABEL_MAX)
    .map(({ room, distance, yaw }) => ({
      id: `room-${room.id}`,
      position: { yaw, pitch: Math.min(0.12, 0.03 + distance / here.width) },
      html: roomTagHtml(tour, room),
      anchor: 'bottom center',
      data: { roomId: room.id, roomCode: room.room_code },
    }));
}

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

function buildNode(tour, point) {
  const plan = tour.pixel(point);
  return {
    id: String(point.id),
    panorama: point.image_url,
    name: pointName(point),
    sphereCorrection: { pan: rad(point.heading || 0) },
    links: tour.neighbors.get(point.id).map((otherId) => {
      const other = tour.pointMap.get(otherId);
      return {
        nodeId: String(otherId),
        position: { yaw: tour.bearing(point, other), pitch: -0.3 },
        data: { name: linkName(tour, point, other) },
      };
    }),
    markers: roomMarkers(tour, point),
    map: { x: plan.x, y: plan.y },
    data: { point },
  };
}

/**
 * สร้างหน้าเดินชมใน container
 * options: startPointId, onNodeChange(point), onRoomTap({roomId, roomCode}), mapSize
 */
export function createTourViewer(container, tour, options = {}) {
  const startPoint = tour.pointMap.get(options.startPointId) || tour.points[0];
  const startPlan = tour.floorMap.get(startPoint.floor);

  const viewer = new Viewer({
    container,
    loadingTxt: 'กำลังโหลดภาพ…',
    navbar: false,
    defaultZoomLvl: 20,
    mousewheelCtrlKey: false,
    touchmoveTwoFingers: false,
    lang: { loadError: 'โหลดภาพไม่สำเร็จ', twoFingers: 'ใช้สองนิ้วเพื่อเลื่อน' },
    // ปิด MSAA: มุมมองทรงกลมมองจากศูนย์กลางมีขอบคมอยู่แค่รอยต่อภาพ (ทำ anti-alias ใน shader แล้ว)
    // MSAA เต็มจอแทบไม่ต่างกับตาเปล่าบนจอมือถือ แต่กินแรงเรนเดอร์ทุกเฟรม โดยเฉพาะบน GPU ที่แปลงผ่านซอฟต์แวร์
    rendererParameters: { antialias: false, powerPreference: 'high-performance' },
    plugins: [
      MarkersPlugin,
      MapPlugin.withConfig({
        imageUrl: startPlan?.image,
        size: options.mapSize || '150px',
        position: 'bottom left',
        shape: 'square',
        // คงผังไว้ทิศเดิมเสมอ (เหมือนแผนผังจริง) แล้วหมุนกรวยบอกทิศแทน ไม่หมุนทั้งแผนผังตามทิศที่มอง
        static: true,
        pinSize: 26,
        coneColor: '#15803D',
        coneSize: 46,
        defaultZoom: 120,
        minimizeOnHotspotClick: true,
        spotStyle: { size: 13, color: '#15803D', borderSize: 2, borderColor: '#ffffff', hoverSize: 17 },
        buttons: { close: false, north: false },
      }),
      VirtualTourPlugin.withConfig({
        positionMode: 'manual',
        renderMode: '3d',
        preload: true,
        startNodeId: String(startPoint.id),
        nodes: tour.points.map((point) => buildNode(tour, point)),
        map: { imageUrl: startPlan?.image },
        showLinkTooltip: false,
        // ซ่อนวงแหวนลูกศรบนพื้น: เดินได้อยู่แล้วด้วยการแตะพื้นในทิศที่ต้องการ (ดู viewer.addEventListener('click', ...)
        // ด้านล่าง) วงแหวนจึงซ้ำซ้อนกับการแตะพื้นแล้วรก ปิด pointer-events ไว้ด้วยกันไปบังการแตะพื้น
        arrowStyle: { size: { width: 80, height: 80 }, style: { opacity: '0', pointerEvents: 'none' } },
        transitionOptions: { showLoader: false, effect: 'fade', speed: 700, rotation: true },
      }),
    ],
  });

  const plugin = viewer.getPlugin(VirtualTourPlugin);
  const map = viewer.getPlugin(MapPlugin);
  const markers = viewer.getPlugin(MarkersPlugin);
  let currentFloor = null;

  // แผนที่มุมจอแสดงเฉพาะจุดในชั้นปัจจุบัน และเปลี่ยนรูปแผนผังเมื่อเดินข้ามชั้น
  function syncMap(point) {
    const spots = tour.points
      .filter((other) => other.floor === point.floor)
      .map((other) => ({ id: MAP_LINK_PREFIX + other.id, ...tour.pixel(other), tooltip: pointName(other) }))
      .map(({ id, x, y, tooltip }) => ({ id, x, y, tooltip }));
    if (point.floor !== currentFloor) {
      currentFloor = point.floor;
      const plan = tour.floorMap.get(point.floor);
      if (plan) map.setImage(plan.image, { x: tour.pixel(point).x, y: tour.pixel(point).y });
    }
    map.setHotspots(spots);
  }

  // มุมเริ่มต้น: ใช้เฉพาะตอนเข้าเดินชมที่จุดแรก (ตอนเดินระหว่างจุดคงทิศที่กำลังมองไว้เพื่อให้ต่อเนื่อง)
  // initial_yaw เก็บเป็นพิกัดภาพต้นฉบับ ลบ heading ออกให้เป็นพิกัดบนจอ
  let startViewApplied = false;
  plugin.addEventListener('node-changed', ({ node }) => {
    const point = node.data.point;
    syncMap(point);
    if (!startViewApplied) {
      startViewApplied = true;
      if (options.useInitialView !== false && point.initial_yaw != null && point.initial_pitch != null) {
        viewer.rotate({ yaw: wrapAngle(point.initial_yaw - rad(point.heading || 0)), pitch: point.initial_pitch });
      }
    }
    options.onNodeChange?.(point);
  });

  markers.addEventListener('select-marker', ({ marker }) => {
    if (marker.data?.roomId) options.onRoomTap?.(marker.data);
  });

  // แตะพื้นแล้วเดินไปทางนั้น (แบบ Street View): เลือกเส้นเชื่อมที่ทิศใกล้กับจุดที่แตะที่สุด
  viewer.addEventListener('click', ({ data }) => {
    if (options.onViewClick?.(data)) return; // โหมดวางป้ายห้องในแดชบอร์ด: ใช้การคลิกเลือกตำแหน่ง ไม่เดินไปจุดอื่น
    if (data.rightclick || data.marker || data.pitch > -0.12) return;
    const node = plugin.getCurrentNode();
    if (!node) return;
    let best = null;
    for (const link of node.links) {
      const diff = Math.abs(wrapAngle(link.position.yaw - data.yaw));
      if (diff <= TAP_WALK_MAX_ANGLE && (!best || diff < best.diff)) best = { link, diff };
    }
    if (best) plugin.setCurrentNode(best.link.nodeId, null, best.link);
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
      const candidates = tour.points.filter((point) => point.floor === floor);
      const linked = candidates.find((point) => tour.neighbors.get(current.id).includes(point.id));
      if (linked) return linked;
      return candidates
        .map((point) => ({ point, distance: Math.hypot(point.x - current.x, point.y - current.y) }))
        .sort((a, b) => a.distance - b.distance)[0]?.point;
    },
    /**
     * ทิศ (heading องศา) ที่ทำให้กึ่งกลางจอตอนนี้ชี้ไปยังจุด targetId บนแผนผัง (ใช้ตั้งทิศในแดชบอร์ด)
     * target เป็นรหัสจุดเดินชม หรือ { roomId } = หมุดของห้องบนแผนผังชั้นเดียวกัน (ใช้เมื่อมีจุดเดินชมแค่จุดเดียว)
     */
    headingFacing(targetId) {
      const current = this.currentPoint;
      const room = targetId?.roomId !== undefined ? tour.rooms.find((item) => item.id === targetId.roomId) : null;
      // { pin: { x, y } } = จุดใดก็ได้บนแผนผังชั้นนี้ (เป็น %) ที่ผู้ดูแลคลิกเลือกเอง เช่น แนวบันได
      const pin = targetId?.pin;
      const target = pin ? { floor: current.floor, x: pin.x, y: pin.y }
        : (room ? { floor: current.floor, x: room.pin_x, y: room.pin_y } : tour.pointMap.get(targetId));
      const viewYaw = viewer.getPosition().yaw;
      const wanted = tour.bearing(current, target);
      // กึ่งกลางจอ (yaw บนจอ v) คือ yaw ในภาพ v + heading ซึ่งต้องกลายเป็นทิศ wanted
      const heading = (current.heading || 0) + deg(wrapAngle(viewYaw - wanted));
      return Math.round(deg(wrapAngle(rad(heading))) * 1000) / 1000;
    },
    destroy() {
      viewer.destroy();
    },
  };
}
