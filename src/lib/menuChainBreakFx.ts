import type { ChainBreakEvent } from "@/lib/menuChains";
import { worldToCanvas } from "@/render/worldToCanvas";

export interface ChainBreakFx {
  born: number;
  ax: number;
  ay: number;
  bx: number;
  by: number;
  side: "left" | "right";
}

const FX_LIFE_MS = 750;

export function spawnChainBreakFx(
  fxs: ChainBreakFx[],
  event: ChainBreakEvent,
  now: number,
): void {
  fxs.push({
    born: now,
    ax: event.anchor.x,
    ay: event.anchor.y,
    bx: event.attach.x,
    by: event.attach.y,
    side: event.side,
  });
}

export function pruneChainBreakFx(fxs: ChainBreakFx[], now: number): ChainBreakFx[] {
  return fxs.filter((fx) => now - fx.born < FX_LIFE_MS);
}

export function drawChainBreakFx(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  fxs: ChainBreakFx[],
  now: number,
  accentColor: string,
): void {
  for (const fx of fxs) {
    const age = now - fx.born;
    if (age > FX_LIFE_MS) continue;
    const t = age / FX_LIFE_MS;

    const anchor = worldToCanvas(render, { x: fx.ax, y: fx.ay });
    const hand = worldToCanvas(render, { x: fx.bx, y: fx.by });
    const mid = {
      x: anchor.x + (hand.x - anchor.x) * 0.55,
      y: anchor.y + (hand.y - anchor.y) * 0.55,
    };

    const burstR = (18 + t * 42) * anchor.scale;
    ctx.save();
    ctx.globalAlpha = (1 - t) * 0.85;
    ctx.strokeStyle = accentColor;
    ctx.lineWidth = 3 * anchor.scale;
    ctx.beginPath();
    ctx.arc(anchor.x, anchor.y, burstR, 0, Math.PI * 2);
    ctx.stroke();

    ctx.globalAlpha = (1 - t) * 0.55;
    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.arc(anchor.x, anchor.y, burstR * 0.35, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    const shards = 10;
    for (let i = 0; i < shards; i++) {
      const angle = (i / shards) * Math.PI * 2 + fx.side.length;
      const dist = (12 + t * 55 + (i % 3) * 8) * anchor.scale;
      const sx = mid.x + Math.cos(angle) * dist;
      const sy = mid.y + Math.sin(angle) * dist;
      const alpha = (1 - t) * 0.9;

      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.translate(sx, sy);
      ctx.rotate(angle + t * 2);
      ctx.fillStyle = i % 2 === 0 ? "rgba(200, 205, 220, 0.95)" : "rgba(130, 135, 155, 0.95)";
      ctx.fillRect(-3 * anchor.scale, -1.5 * anchor.scale, 6 * anchor.scale, 3 * anchor.scale);
      ctx.restore();
    }

    ctx.save();
    ctx.globalAlpha = (1 - t) * 0.7;
    ctx.strokeStyle = "rgba(255, 255, 255, 0.9)";
    ctx.lineWidth = 2.5 * anchor.scale;
    ctx.setLineDash([6 * anchor.scale, 5 * anchor.scale]);
    ctx.lineDashOffset = -t * 40;
    ctx.beginPath();
    ctx.moveTo(anchor.x, anchor.y);
    ctx.lineTo(hand.x, hand.y);
    ctx.stroke();
    ctx.restore();
  }
}
