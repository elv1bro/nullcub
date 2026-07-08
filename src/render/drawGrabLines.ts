import type { Render } from "matter-js";
import type { GrabVisualLine } from "@/lib/grab/types";

export function drawGrabLines(
  ctx: CanvasRenderingContext2D,
  _render: Render,
  lines: GrabVisualLine[],
): void {
  if (!lines.length) return;

  ctx.save();
  ctx.setLineDash([6, 4]);
  ctx.lineWidth = 3;
  for (const line of lines) {
    ctx.beginPath();
    ctx.moveTo(line.from.x, line.from.y);
    ctx.lineTo(line.to.x, line.to.y);
    ctx.strokeStyle = line.color;
    ctx.stroke();
  }
  ctx.restore();
}
