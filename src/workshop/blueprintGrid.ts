import type Matter from "matter-js";
import { worldToCanvas } from "@/render/worldToCanvas";

/** Grid step in world units. */
export const BLUEPRINT_GRID = 20;

export const BLUEPRINT = {
  paper: "#0a3d6b",
  paperDeep: "#071e3a",
  dot: "rgba(186, 230, 253, 0.7)",
  dotMajor: "rgba(224, 242, 254, 0.9)",
  lineMajor: "rgba(191, 219, 254, 0.4)",
  border: "rgba(224, 242, 254, 0.4)",
  crosshair: "rgba(224, 242, 254, 0.75)",
  label: "rgba(224, 242, 254, 0.85)",
  silhouette: "rgba(148, 163, 184, 0.55)",
  silhouetteStroke: "rgba(226, 232, 240, 0.75)",
  silhouetteLabel: "rgba(226, 232, 240, 0.85)",
} as const;

export function snapToGrid(point: Matter.Vector): Matter.Vector {
  return {
    x: Math.round(point.x / BLUEPRINT_GRID) * BLUEPRINT_GRID,
    y: Math.round(point.y / BLUEPRINT_GRID) * BLUEPRINT_GRID,
  };
}

function drawHumanSilhouette(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  origin: Matter.Vector,
): void {
  const w = (dx: number, dy: number) =>
    worldToCanvas(render, { x: origin.x + dx, y: origin.y + dy });

  const head = w(0, -72);
  const neck = w(0, -48);
  const hip = w(0, 10);
  const lFoot = w(-18, 78);
  const rFoot = w(18, 78);
  const lHand = w(-42, -8);
  const rHand = w(42, -8);
  const scale = head.scale;

  ctx.save();
  ctx.strokeStyle = BLUEPRINT.silhouetteStroke;
  ctx.fillStyle = BLUEPRINT.silhouette;
  ctx.lineWidth = 3 * scale;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  ctx.beginPath();
  ctx.arc(head.x, head.y, 22 * scale, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  ctx.lineWidth = 3.5 * scale;

  ctx.beginPath();
  ctx.moveTo(neck.x, neck.y);
  ctx.lineTo(hip.x, hip.y);
  ctx.moveTo(neck.x + 8 * scale, neck.y + 6 * scale);
  ctx.lineTo(lHand.x, lHand.y);
  ctx.moveTo(neck.x - 8 * scale, neck.y + 6 * scale);
  ctx.lineTo(rHand.x, rHand.y);
  ctx.moveTo(hip.x, hip.y);
  ctx.lineTo(lFoot.x, lFoot.y);
  ctx.moveTo(hip.x, hip.y);
  ctx.lineTo(rFoot.x, rFoot.y);
  ctx.stroke();

  ctx.font = `700 ${11 * scale}px Rubik, system-ui, sans-serif`;
  ctx.fillStyle = BLUEPRINT.silhouetteLabel;
  ctx.textAlign = "center";
  ctx.fillText("~160px", lFoot.x - 6 * scale, lFoot.y + 14 * scale);

  ctx.restore();
}

function drawAxisLabels(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  origin: Matter.Vector,
): void {
  const labelStep = 100;
  const fontSize = 10;
  ctx.save();
  ctx.fillStyle = BLUEPRINT.label;
  ctx.font = `600 ${fontSize}px Rubik, system-ui, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";

  const o = worldToCanvas(render, origin);
  ctx.fillText("0", o.x + 14, o.y - 14);

  for (let d = -400; d <= 400; d += labelStep) {
    if (d === 0) continue;
    const wx = origin.x + d;
    const wy = origin.y + d;
    if (wx >= render.bounds.min.x && wx <= render.bounds.max.x) {
      const p = worldToCanvas(render, { x: wx, y: origin.y });
      ctx.fillText(d > 0 ? `+${d}` : `${d}`, p.x, p.y + 16);
    }
    if (wy >= render.bounds.min.y && wy <= render.bounds.max.y) {
      const p = worldToCanvas(render, { x: origin.x, y: wy });
      ctx.textAlign = "right";
      ctx.fillText(d > 0 ? `+${d}` : `${d}`, p.x - 10, p.y);
      ctx.textAlign = "center";
    }
  }

  const xEnd = worldToCanvas(render, {
    x: render.bounds.max.x - 40,
    y: origin.y,
  });
  const yEnd = worldToCanvas(render, {
    x: origin.x,
    y: render.bounds.min.y + 30,
  });
  ctx.font = `700 ${fontSize + 1}px Rubik, sans-serif`;
  ctx.fillStyle = "rgba(224, 242, 254, 0.9)";
  ctx.fillText("X", xEnd.x, xEnd.y + 16);
  ctx.textAlign = "right";
  ctx.fillText("Y", yEnd.x - 8, yEnd.y);
  ctx.restore();
}

/**
 * Draw the full blueprint background.
 *
 * IMPORTANT: This must be called inside `afterRender` with
 * `globalCompositeOperation = "destination-over"` so that the grid
 * appears behind physics bodies. The background gradient is drawn LAST
 * so it ends up furthest back (behind grid dots and bodies).
 */
export function drawBlueprint(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  center: Matter.Vector,
): void {
  const { bounds, canvas } = render;
  const w = canvas.width;
  const h = canvas.height;

  // --- Layer 1: grid elements (drawn first → closer to bodies) ---

  drawHumanSilhouette(ctx, render, center);

  const step = BLUEPRINT_GRID;
  const major = step * 5;
  const startX = Math.floor(bounds.min.x / step) * step;
  const startY = Math.floor(bounds.min.y / step) * step;

  for (let wx = startX; wx <= bounds.max.x; wx += step) {
    for (let wy = startY; wy <= bounds.max.y; wy += step) {
      const isMajor = wx % major === 0 && wy % major === 0;
      const p = worldToCanvas(render, { x: wx, y: wy });
      ctx.fillStyle = isMajor ? BLUEPRINT.dotMajor : BLUEPRINT.dot;
      ctx.beginPath();
      ctx.arc(p.x, p.y, isMajor ? 2.5 : 1.5, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  ctx.lineWidth = 1;
  for (let wx = Math.floor(bounds.min.x / major) * major; wx <= bounds.max.x; wx += major) {
    const a = worldToCanvas(render, { x: wx, y: bounds.min.y });
    const b = worldToCanvas(render, { x: wx, y: bounds.max.y });
    ctx.strokeStyle = wx === center.x ? BLUEPRINT.crosshair : BLUEPRINT.lineMajor;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
  }
  for (let wy = Math.floor(bounds.min.y / major) * major; wy <= bounds.max.y; wy += major) {
    const a = worldToCanvas(render, { x: bounds.min.x, y: wy });
    const b = worldToCanvas(render, { x: bounds.max.x, y: wy });
    ctx.strokeStyle = wy === center.y ? BLUEPRINT.crosshair : BLUEPRINT.lineMajor;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
  }

  const c = worldToCanvas(render, center);
  ctx.strokeStyle = BLUEPRINT.crosshair;
  ctx.lineWidth = 1.5;
  ctx.setLineDash([]);
  ctx.beginPath();
  ctx.moveTo(c.x - 36, c.y);
  ctx.lineTo(c.x + 36, c.y);
  ctx.moveTo(c.x, c.y - 36);
  ctx.lineTo(c.x, c.y + 36);
  ctx.stroke();

  drawAxisLabels(ctx, render, center);

  const pad = 36;
  const tl = worldToCanvas(render, { x: bounds.min.x, y: bounds.min.y });
  const br = worldToCanvas(render, { x: bounds.max.x, y: bounds.max.y });
  ctx.strokeStyle = BLUEPRINT.border;
  ctx.lineWidth = 1.5;
  ctx.strokeRect(tl.x + pad, tl.y + pad, br.x - tl.x - pad * 2, br.y - tl.y - pad * 2);

  // --- Layer 2: background gradient (drawn last → furthest back) ---

  const bg = ctx.createLinearGradient(0, 0, w, h);
  bg.addColorStop(0, "#0e5a94");
  bg.addColorStop(0.45, BLUEPRINT.paper);
  bg.addColorStop(1, BLUEPRINT.paperDeep);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, w, h);

  const vignette = ctx.createRadialGradient(
    w * 0.5,
    h * 0.45,
    Math.min(w, h) * 0.15,
    w * 0.5,
    h * 0.5,
    Math.max(w, h) * 0.72,
  );
  vignette.addColorStop(0, "rgba(255,255,255,0.04)");
  vignette.addColorStop(1, "rgba(0,0,0,0.22)");
  ctx.fillStyle = vignette;
  ctx.fillRect(0, 0, w, h);
}
