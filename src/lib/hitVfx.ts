import type Matter from "matter-js";
import { worldToCanvas } from "@/render/worldToCanvas";

export interface HitBurst {
  x: number;
  y: number;
  born: number;
  color: string;
  secondary: string;
  /** 0–1 от силы удара */
  power: number;
}

export const BURST_LIFE_MS = 520;

export function pruneBursts(bursts: HitBurst[], now: number): HitBurst[] {
  return bursts.filter((b) => now - b.born < BURST_LIFE_MS);
}

export function drawHitBursts(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  bursts: HitBurst[],
  now: number,
): void {
  for (const burst of bursts) {
    const age = now - burst.born;
    if (age > BURST_LIFE_MS) continue;

    const t = age / BURST_LIFE_MS;
    const alpha = 1 - t * t;
    const { x, y, scale } = worldToCanvas(render, { x: burst.x, y: burst.y });
    const r = (18 + burst.power * 42) * scale * (0.4 + t * 1.6);

    ctx.save();
    ctx.globalAlpha = alpha * 0.55;
    ctx.strokeStyle = burst.color;
    ctx.lineWidth = Math.max(2, 3 * scale * (1 - t * 0.5));
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.stroke();

    ctx.globalAlpha = alpha * 0.9;
    const sparks = 10;
    for (let i = 0; i < sparks; i++) {
      const a = (i / sparks) * Math.PI * 2 + burst.power;
      const len = r * (0.35 + burst.power * 0.45);
      ctx.strokeStyle = i % 2 === 0 ? burst.color : burst.secondary;
      ctx.lineWidth = Math.max(1.5, 2.5 * scale);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len);
      ctx.stroke();
    }

    ctx.globalAlpha = alpha * 0.35;
    ctx.fillStyle = burst.color;
    ctx.beginPath();
    ctx.arc(x, y, r * 0.22, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }
}
