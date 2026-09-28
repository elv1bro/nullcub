import type Matter from "matter-js";
import { worldToCanvas } from "@/render/worldToCanvas";

/** Красный outline вокруг частей, не связанных с головой. */
export function drawWorkshopOrphans(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  composite: Matter.Composite,
  orphanIndices: number[],
): void {
  if (orphanIndices.length === 0) return;
  ctx.save();
  ctx.strokeStyle = "rgba(248, 113, 113, 0.95)";
  ctx.lineWidth = 3;
  ctx.setLineDash([6, 4]);
  for (const index of orphanIndices) {
    const body = composite.bodies[index];
    if (!body) continue;
    const r = (body.circleRadius ?? 10) + 4;
    const p = worldToCanvas(render, body.position);
    ctx.beginPath();
    ctx.arc(p.x, p.y, r * p.scale, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.restore();
}
