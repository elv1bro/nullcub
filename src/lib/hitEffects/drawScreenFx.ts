import type Matter from "matter-js";
import type { FighterColors } from "@/lib/fighterColors";
import type { FighterSide } from "@/lib/useHealth";
import { worldToCanvas } from "@/render/worldToCanvas";
import { SHOCKWAVE_LIFE_MS, type HitEffectStore } from "./store";
import { comboLabel } from "./comboAnnouncer";

function colorsForSide(
  side: FighterSide,
  playerColors: FighterColors,
  opponentColors: FighterColors,
): FighterColors {
  return side === "player" ? playerColors : opponentColors;
}

export function sampleShake(store: HitEffectStore, now: number): { dx: number; dy: number } {
  if (store.shake.until <= now || store.shake.intensity <= 0) {
    return { dx: 0, dy: 0 };
  }
  const t = (store.shake.until - now) / 220;
  const amp = store.shake.intensity * Math.max(0, Math.min(1, t));
  return {
    dx: (Math.random() - 0.5) * amp * 2,
    dy: (Math.random() - 0.5) * amp * 2,
  };
}

export function applyCameraShake(render: Matter.Render, dx: number, dy: number): void {
  if (!dx && !dy) return;
  const bw = render.bounds.max.x - render.bounds.min.x;
  const bh = render.bounds.max.y - render.bounds.min.y;
  const worldDx = (dx / render.canvas.width) * bw;
  const worldDy = (dy / render.canvas.height) * bh;
  render.bounds.min.x -= worldDx;
  render.bounds.max.x -= worldDx;
  render.bounds.min.y -= worldDy;
  render.bounds.max.y -= worldDy;
}

/** Finisher zoom к победителю (#12). */
export function applyFinisherCam(render: Matter.Render, store: HitEffectStore, now: number): void {
  const fin = store.finisher;
  if (!fin || now >= fin.until) return;

  const t = 1 - (fin.until - now) / 2200;
  const ease = t < 0.2 ? t / 0.2 : 1;
  const zoom = 1 - (1 - fin.zoom) * ease;

  const cx = fin.focusX;
  const cy = fin.focusY;
  const halfW = ((render.bounds.max.x - render.bounds.min.x) * zoom) / 2;
  const halfH = ((render.bounds.max.y - render.bounds.min.y) * zoom) / 2;

  render.bounds.min.x = cx - halfW;
  render.bounds.max.x = cx + halfW;
  render.bounds.min.y = cy - halfH;
  render.bounds.max.y = cy + halfH;
}

export function drawGroundShockwaves(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  now: number,
): void {
  for (const wave of store.shockwaves) {
    const age = now - wave.born;
    if (age > SHOCKWAVE_LIFE_MS) continue;
    const t = age / SHOCKWAVE_LIFE_MS;
    const alpha = (1 - t) * 0.75;
    const { x, y, scale } = worldToCanvas(render, { x: wave.x, y: wave.y });
    const rx = (40 + wave.power * 120) * scale * (0.35 + t * 1.4);
    const ry = rx * 0.28;

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = wave.color;
    ctx.lineWidth = Math.max(2, 4 * scale * (1 - t * 0.5));
    ctx.beginPath();
    ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = alpha * 0.35;
    ctx.fillStyle = wave.color;
    ctx.fill();
    ctx.restore();
  }
}

export function drawScreenFlash(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  now: number,
): void {
  const flash = store.flash;
  if (!flash || now >= flash.until) return;
  const left = flash.until - now;
  const alpha = flash.alpha * Math.min(1, left / 80);
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = flash.color;
  ctx.fillRect(0, 0, render.canvas.width, render.canvas.height);
  ctx.restore();
}

export function drawFinisherVignette(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  now: number,
): void {
  const fin = store.finisher;
  if (!fin || now >= fin.until) return;
  const t = 1 - (fin.until - now) / 2200;
  const alpha = Math.min(0.72, 0.25 + t * 0.45);
  const { width, height } = render.canvas;
  const grad = ctx.createRadialGradient(
    width / 2,
    height / 2,
    Math.min(width, height) * 0.15,
    width / 2,
    height / 2,
    Math.max(width, height) * 0.72,
  );
  grad.addColorStop(0, "rgba(0,0,0,0)");
  grad.addColorStop(1, `rgba(0,0,0,${alpha})`);
  ctx.save();
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);
  ctx.restore();
}

export function drawComboAndAnnouncer(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  language: "en" | "ru",
  now: number,
  playerColors: FighterColors,
  opponentColors: FighterColors,
): void {
  const combo = store.combo;
  if (combo && combo.count >= 2 && now - combo.lastHitAt < 900) {
    const label = comboLabel(combo.count, language);
    const pulse = 1 + Math.sin(now / 80) * 0.06;
    const fontSize = Math.max(22, render.canvas.width * 0.034) * pulse;
    const colors = colorsForSide(combo.side, playerColors, opponentColors);
    ctx.save();
    ctx.font = `800 ${fontSize}px Unbounded, Rubik, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    ctx.lineWidth = 4;
    ctx.strokeStyle = colors.secondary;
    ctx.strokeText(label, render.canvas.width / 2, 18);
    ctx.fillStyle = colors.main;
    ctx.fillText(label, render.canvas.width / 2, 18);
    ctx.restore();
  }
}
