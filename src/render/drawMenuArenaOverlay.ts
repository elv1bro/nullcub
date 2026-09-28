import type Matter from "matter-js";
import { chainAnchors, chainSegments, type MenuChainSet } from "@/lib/menuChains";
import type { EscapeQuip } from "@/lib/menuEscapeQuips";
import { renderCssSize, worldToCanvas } from "./worldToCanvas";

interface TitleOpts {
  line1: string;
  line2: string;
  accentColor: string;
}

/** Две строки заголовка — всё название видно. */
export function drawMenuArenaTitle(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  opts: TitleOpts,
  now: number,
): void {
  const { bounds } = render;
  const { width } = renderCssSize(render);
  const cx = (bounds.min.x + bounds.max.x) / 2;
  const topY = bounds.min.y + (bounds.max.y - bounds.min.y) * 0.06;
  const bob = Math.sin(now / 900) * 4;
  const { x, y, scale } = worldToCanvas(render, { x: cx, y: topY + bob });

  const line1Size = Math.max(22, Math.min(36, width * 0.032 * scale));
  const line2Size = line1Size * 1.15;
  const gap = line1Size * 0.55;

  ctx.save();
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = `800 ${line1Size}px Unbounded, Rubik, sans-serif`;
  ctx.lineWidth = Math.max(2, line1Size * 0.07);
  ctx.strokeStyle = "rgba(0,0,0,0.7)";
  ctx.strokeText(opts.line1, x, y);
  ctx.fillStyle = "rgba(255,255,255,0.94)";
  ctx.fillText(opts.line1, x, y);

  ctx.font = `800 ${line2Size}px Unbounded, Rubik, sans-serif`;
  ctx.strokeText(opts.line2, x, y + gap);
  ctx.fillStyle = opts.accentColor;
  ctx.shadowColor = opts.accentColor;
  ctx.shadowBlur = 12;
  ctx.fillText(opts.line2, x, y + gap);
  ctx.restore();
}

/** Нарисовать платформу под бойцом. */
export function drawMenuPlatform(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  platform: Matter.Body | null,
  accentColor: string,
): void {
  if (!platform) return;

  const b = platform.bounds;
  const tl = worldToCanvas(render, { x: b.min.x, y: b.min.y });
  const br = worldToCanvas(render, { x: b.max.x, y: b.max.y });
  const w = br.x - tl.x;
  const h = br.y - tl.y;

  ctx.save();
  const grad = ctx.createLinearGradient(tl.x, tl.y, tl.x, tl.y + h);
  grad.addColorStop(0, "#2a2a3a");
  grad.addColorStop(1, "#14141c");
  ctx.fillStyle = grad;
  ctx.fillRect(tl.x, tl.y, w, h);

  ctx.strokeStyle = accentColor;
  ctx.globalAlpha = 0.35;
  ctx.lineWidth = 2;
  ctx.strokeRect(tl.x + 1, tl.y + 1, w - 2, h - 2);
  ctx.globalAlpha = 1;
  ctx.restore();
}

/** Красивые цепи — звенья вдоль сегмента. */
export function drawMenuChains(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  chainSet: MenuChainSet | null,
  composite: Matter.Composite | null | undefined,
  now: number,
): void {
  if (!chainSet || chainSet.links.length === 0 || !composite) return;

  for (const anchor of chainAnchors(chainSet)) {
    drawWallRing(ctx, render, anchor, now);
  }

  for (const seg of chainSegments(chainSet, composite)) {
    const a = worldToCanvas(render, { x: seg.ax, y: seg.ay });
    const b = worldToCanvas(render, { x: seg.bx, y: seg.by });
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.hypot(dx, dy);
    if (len < 4) continue;

    const links = Math.max(8, Math.floor(len / 14));
    const nx = dx / len;
    const ny = dy / len;
    const px = -ny;
    const py = nx;

    ctx.save();
    for (let i = 0; i <= links; i++) {
      const t = i / links;
      const wobble = Math.sin(now / 120 + i * 0.9) * 2;
      const cx = a.x + dx * t + px * wobble;
      const cy = a.y + dy * t + py * wobble;
      const r = 4.5 + (i % 2) * 0.8;

      ctx.beginPath();
      ctx.ellipse(cx, cy, r, r * 0.72, Math.atan2(dy, dx), 0, Math.PI * 2);
      ctx.fillStyle =
        i % 2 === 0 ? "rgba(170, 175, 195, 0.95)" : "rgba(110, 115, 135, 0.95)";
      ctx.fill();
      ctx.strokeStyle = "rgba(40, 42, 55, 0.9)";
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }

    ctx.strokeStyle = "rgba(90, 95, 115, 0.35)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
    ctx.restore();
  }
}

function drawWallRing(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  anchor: Matter.Vector,
  now: number,
): void {
  const { x, y, scale } = worldToCanvas(render, anchor);
  const pulse = 1 + Math.sin(now / 400) * 0.04;
  const r = 11 * scale * pulse;

  ctx.save();
  ctx.strokeStyle = "rgba(160, 165, 185, 0.95)";
  ctx.lineWidth = 3.5 * scale;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.stroke();
  ctx.strokeStyle = "rgba(80, 85, 100, 0.8)";
  ctx.lineWidth = 1.5 * scale;
  ctx.beginPath();
  ctx.arc(x, y, r * 0.55, 0, Math.PI * 2);
  ctx.stroke();
  ctx.fillStyle = "rgba(20, 22, 32, 0.5)";
  ctx.fill();
  ctx.restore();
}

/** «GO GO GO» рядом с бойцом при рывке. */
export function drawEscapeQuips(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  quips: EscapeQuip[],
  headX: number,
  headY: number,
  now: number,
): void {
  const head = worldToCanvas(render, { x: headX, y: headY });

  for (const quip of quips) {
    const age = now - quip.born;
    if (age > 900) continue;
    const t = age / 900;
    const alpha = (1 - t) * 0.95;
    const offsetX = quip.side === "left" ? -90 - age * 0.08 : 90 + age * 0.08;
    const offsetY = -40 - age * 0.12 + Math.sin(age / 80) * 8;
    const fontSize = Math.max(16, 22 * (1 - t * 0.2));

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.font = `800 ${fontSize}px Unbounded, Rubik, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.translate(head.x + offsetX, head.y + offsetY);
    ctx.rotate(quip.side === "left" ? -0.12 : 0.12);
    ctx.lineWidth = 3;
    ctx.strokeStyle = "rgba(0,0,0,0.75)";
    ctx.strokeText(quip.text, 0, 0);
    ctx.fillStyle = quip.side === "left" ? "#93c5fd" : "#fde047";
    ctx.fillText(quip.text, 0, 0);
    ctx.restore();
  }
}
