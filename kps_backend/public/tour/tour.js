// หน้าเดินชมอาคาร (ใช้ร่วมกันระหว่างหน้า /tour/ ในแอป และหน้าดูตัวอย่างในแดชบอร์ด)
// ข้อมูลมาจาก GET /api/tour/:buildingId — จุดถ่ายวางบนแผนผังเป็น % ผู้ใช้เลือกจุดที่จะดูจาก "แผนที่ย่อ" มุมจอ
// (แตะจุดสีเขียวเพื่อไปดูภาพนั้น) ไม่มีการเดินต่อเนื่อง ไม่ใช้ทิศของภาพ และไม่มีป้ายห้องลอยในภาพ
import { Viewer, SYSTEM } from '@photo-sphere-viewer/core';
import { VirtualTourPlugin } from '@photo-sphere-viewer/virtual-tour-plugin';
import { MapPlugin } from '@photo-sphere-viewer/map-plugin';

// จอมือถือความละเอียดสูง (devicePixelRatio 3 ขึ้นไป) ทำให้ WebGL ต้องเรนเดอร์ทุกพิกเซลจริงของจอ
// บวก MSAA เต็มรูปแบบ บนมือถือจำลอง/เครื่องเก่าจะกระตุกมาก จึงจำกัดไว้ไม่เกิน 2 และปิด MSAA
SYSTEM.load();
SYSTEM.pixelRatio = Math.min(SYSTEM.pixelRatio, 2);

const MAP_LINK_PREFIX = '__tour-link__'; // id ที่ VirtualTourPlugin ใช้กับจุดบนแผนที่ (แตะแล้วไปจุดนั้นให้เอง)

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

// ไม่มีลิงก์ระหว่างจุด (ปลั๊กอินจะวาดลูกศรบนพื้นให้ทุกลิงก์) ผู้ใช้เลือกจุดจากแผนที่ย่อ ดู select-hotspot ด้านล่าง
function buildNode(tour, point) {
  const plan = tour.pixel(point);
  return {
    id: String(point.id),
    panorama: point.image_url,
    name: pointName(point),
    links: [],
    map: { x: plan.x, y: plan.y },
    data: { point },
  };
}

/**
 * สร้างหน้าเดินชมใน container
 * options: startPointId, onNodeChange(point), mapSize, useInitialView (ค่าเริ่มต้น true = เปิดจุดแรกที่มุมเริ่มต้นที่ตั้งไว้)
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
    rendererParameters: { antialias: false, powerPreference: 'high-performance' },
    plugins: [
      MapPlugin.withConfig({
        imageUrl: startPlan?.image,
        size: options.mapSize || '150px',
        position: 'bottom left',
        shape: 'square',
        static: true,
        pinSize: 26,
        // ไม่รู้ทิศของภาพ จึงซ่อนกรวยทิศ เหลือแค่จุดตำแหน่ง
        coneColor: 'rgba(0,0,0,0)',
        coneSize: 1,
        defaultZoom: 100,
        minZoom: 5,
        minimizeOnHotspotClick: true,
        spotStyle: { size: 13, color: '#15803D', borderSize: 2, borderColor: '#ffffff', hoverSize: 17 },
        buttons: { close: false, north: false },
      }),
      VirtualTourPlugin.withConfig({
        positionMode: 'manual',
        renderMode: '3d',
        preload: false,
        startNodeId: String(startPoint.id),
        nodes: tour.points.map((point) => buildNode(tour, point)),
        map: { imageUrl: startPlan?.image },
        showLinkTooltip: false,
        transitionOptions: { showLoader: false, effect: 'fade', speed: 700, rotation: false },
      }),
    ],
  });

  const plugin = viewer.getPlugin(VirtualTourPlugin);
  const map = viewer.getPlugin(MapPlugin);
  let currentFloor = null;

  // แผนที่มุมจอแสดงเฉพาะจุดในชั้นปัจจุบัน ซูมให้เห็นทุกจุดของชั้น (จุดที่ยืนอยู่อยู่กึ่งกลางเสมอ
  // จึงยึดจุดที่อยู่ไกลที่สุดเป็นเกณฑ์) และเปลี่ยนรูปแผนผังเมื่อสลับชั้น
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
    const here = tour.pixel(point);
    const farthest = spots.reduce((max, spot) => Math.max(max, Math.hypot(spot.x - here.x, spot.y - here.y)), 1);
    const size = Number.parseInt(options.mapSize, 10) || 150;
    map.setZoom(Math.max(5, Math.min(200, ((size / 2) * 0.8) / farthest * 100)));
  }

  // มุมเริ่มต้น: ใช้เฉพาะตอนเข้าเดินชมที่จุดแรก (ตอนไปจุดอื่นเริ่มที่มุมที่กำลังมองอยู่)
  let startViewApplied = false;
  plugin.addEventListener('node-changed', ({ node }) => {
    const point = node.data.point;
    syncMap(point);
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
      viewer.destroy();
    },
  };
}
