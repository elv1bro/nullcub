import Matter from "matter-js";
import { worldToCanvas } from "./worldToCanvas";

export function drawBodySpeeds(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  composite: Matter.Composite,
  label: string,
  color: string,
  offsetY: number,
): void {
  const head = composite.bodies.find((b) => b.label === "Head") ?? composite.bodies[0];
  if (!head) return;

  const avg =
    composite.bodies.reduce((s, b) => s + Matter.Vector.magnitude(b.velocity), 0) /
    composite.bodies.length;

  const max = Math.max(
    ...composite.bodies.map((b) => Matter.Vector.magnitude(b.velocity)),
  );

  const { x, y, scale } = worldToCanvas(render, {
    x: head.position.x,
    y: head.position.y - 80,
  });

  ctx.save();
  ctx.font = `600 ${Math.max(10, 11 * scale)}px monospace`;
  ctx.textAlign = "center";
  ctx.fillStyle = color;
  ctx.strokeStyle = "rgba(0,0,0,0.85)";
  ctx.lineWidth = 3;
  const text = `${label} avg ${avg.toFixed(1)} max ${max.toFixed(1)}`;
  ctx.strokeText(text, x, y + offsetY);
  ctx.fillText(text, x, y + offsetY);
  ctx.restore();
}

export function drawHitDebug(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  x: number,
  y: number,
  text: string,
): void {
  const p = worldToCanvas(render, { x, y });
  ctx.save();
  ctx.font = "600 11px monospace";
  ctx.fillStyle = "#ffe135";
  ctx.strokeStyle = "#000";
  ctx.lineWidth = 2;
  ctx.strokeText(text, p.x, p.y - 20);
  ctx.fillText(text, p.x, p.y - 20);
  ctx.restore();
}
