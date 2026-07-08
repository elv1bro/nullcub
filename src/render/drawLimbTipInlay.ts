import type Matter from "matter-js";
import { isSaveBody } from "@/lib/isSaveBody";
import { worldToCanvas } from "./worldToCanvas";

/** Доля радиуса, которую занимает второй цвет в центре кончика. */
export const LIMB_TIP_INLAY_RATIO = 0.5;

/** Второй цвет — только центр кончика; кольцо рисует Matter (основной fill). */
export function drawLimbTipInlays(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  composite: Matter.Composite,
  inlayColor: string,
): void {
  for (const body of composite.bodies) {
    if (!isSaveBody(body)) continue;

    const r = body.circleRadius ?? 10;
    const innerR = r * LIMB_TIP_INLAY_RATIO;
    const { x, y, scale } = worldToCanvas(render, body.position);

    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(body.angle);
    ctx.fillStyle = inlayColor;
    ctx.beginPath();
    ctx.arc(0, 0, innerR * scale, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}
