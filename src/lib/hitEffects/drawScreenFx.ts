import type Matter from "matter-js";
import type { FighterColors } from "@/lib/fighterColors";
import type { FighterSide } from "@/lib/useHealth";
import { renderCssSize, worldToCanvas } from "@/render/worldToCanvas";
import {
  COMBO_SPARK_LIFE_MS,
  FINISHER_MS,
  IMPACT_CAM_MS,
  SHOCKWAVE_LIFE_MS,
  type HitEffectStore,
} from "./store";
import { comboLabel } from "./comboAnnouncer";

function colorsForSide(
  side: FighterSide,
  playerColors: FighterColors,
  opponentColors: FighterColors,
): FighterColors {
  return side === "player" ? playerColors : opponentColors;
}

export function sampleShake(store: HitEffectStore, now: number): { dx: number; dy: number } {
  let amp = 0;
  if (store.shake.until > now && store.shake.intensity > 0) {
    const t = (store.shake.until - now) / 220;
    amp = store.shake.intensity * Math.max(0, Math.min(1, t));
  }
  // Finisher «thrash» — дрожь камеры пока зум на голове.
  const fin = store.finisher;
  if (fin && now < fin.until) {
    const life = (fin.until - now) / FINISHER_MS;
    amp = Math.max(amp, 3 + life * 10);
  }
  if (amp <= 0) return { dx: 0, dy: 0 };
  return {
    dx: (Math.random() - 0.5) * amp * 2,
    dy: (Math.random() - 0.5) * amp * 2,
  };
}

export function applyCameraShake(render: Matter.Render, dx: number, dy: number): void {
  if (!dx && !dy) return;
  const bw = render.bounds.max.x - render.bounds.min.x;
  const bh = render.bounds.max.y - render.bounds.min.y;
  const { width, height } = renderCssSize(render);
  const worldDx = (dx / width) * bw;
  const worldDy = (dy / height) * bh;
  render.bounds.min.x -= worldDx;
  render.bounds.max.x -= worldDx;
  render.bounds.min.y -= worldDy;
  render.bounds.max.y -= worldDy;
}

function applyZoomCam(
  render: Matter.Render,
  focusX: number,
  focusY: number,
  zoom: number,
  ease: number,
): void {
  const z = 1 - (1 - zoom) * ease;
  const halfW = ((render.bounds.max.x - render.bounds.min.x) * z) / 2;
  const halfH = ((render.bounds.max.y - render.bounds.min.y) * z) / 2;
  render.bounds.min.x = focusX - halfW;
  render.bounds.max.x = focusX + halfW;
  render.bounds.min.y = focusY - halfH;
  render.bounds.max.y = focusY + halfH;
}

/** Finisher zoom к победителю (#12). */
export function applyFinisherCam(render: Matter.Render, store: HitEffectStore, now: number): void {
  const fin = store.finisher;
  if (!fin || now >= fin.until) return;

  const t = 1 - (fin.until - now) / FINISHER_MS;
  const ease = t < 0.12 ? t / 0.12 : 1;
  applyZoomCam(render, fin.focusX, fin.focusY, fin.zoom, ease);
}

/** Короткий punch на тяжёлый удар. */
export function applyImpactCam(render: Matter.Render, store: HitEffectStore, now: number): void {
  if (store.finisher && now < store.finisher.until) return;
  const cam = store.impactCam;
  if (!cam || now >= cam.until) return;
  const t = 1 - (cam.until - now) / IMPACT_CAM_MS;
  const ease = t < 0.35 ? t / 0.35 : 1 - (t - 0.35) * 0.4;
  applyZoomCam(render, cam.focusX, cam.focusY, cam.zoom, Math.max(0, Math.min(1, ease)));
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
  const { width, height } = renderCssSize(render);
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = flash.color;
  ctx.fillRect(0, 0, width, height);
  ctx.restore();
}

/**
 * 2–3 кадра «вспышки» на суперхит. Раньше было saturation+difference на весь
 * канвас — на серии тяжёлых ударов GPU проседал; одного полупрозрачного
 * fillRect хватает для того же удара по глазу.
 */
export function drawImpactFrames(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  now: number,
): void {
  if (now >= store.impactInvertUntil) return;
  const { width, height } = renderCssSize(render);
  const left = store.impactInvertUntil - now;
  const flicker = Math.floor(left / 18) % 2 === 0;
  ctx.save();
  ctx.globalAlpha = flicker ? 0.38 : 0.22;
  ctx.fillStyle = "#f8fafc";
  ctx.fillRect(0, 0, width, height);
  ctx.restore();
}

/** Искры на комбо ×5. */
export function drawComboSparks(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  now: number,
): void {
  for (const burst of store.comboSparks) {
    const age = now - burst.born;
    if (age > COMBO_SPARK_LIFE_MS) continue;
    const t = age / COMBO_SPARK_LIFE_MS;
    const alpha = (1 - t) * (0.55 + burst.power * 0.4);
    const { x, y, scale } = worldToCanvas(render, { x: burst.x, y: burst.y });
    // Меньше arc'ов: на ×5 комбо и так уже тряска + flash.
    const n = 10 + Math.floor(burst.power * 6);
    ctx.save();
    for (let i = 0; i < n; i++) {
      const seed = i * 2.17 + burst.born * 0.001;
      const ang = seed * 1.7;
      const dist = (12 + (i % 7) * 10 + t * (40 + burst.power * 70)) * scale;
      const px = x + Math.cos(ang) * dist;
      const py = y + Math.sin(ang) * dist - t * 28 * scale;
      const r = Math.max(1.2, (2.2 + (i % 3)) * scale * (1 - t * 0.6));
      ctx.globalAlpha = alpha * (i % 2 === 0 ? 1 : 0.7);
      ctx.fillStyle = i % 2 === 0 ? burst.color : burst.secondary;
      ctx.beginPath();
      ctx.arc(px, py, r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }
}

export function drawFinisherVignette(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  store: HitEffectStore,
  now: number,
): void {
  const fin = store.finisher;
  if (!fin || now >= fin.until) return;
  const t = 1 - (fin.until - now) / FINISHER_MS;
  const alpha = Math.min(0.78, 0.28 + t * 0.5);
  const { width, height } = renderCssSize(render);
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
    const { width } = renderCssSize(render);
    const fontSize = Math.max(22, width * 0.034) * pulse;
    const colors = colorsForSide(combo.side, playerColors, opponentColors);
    ctx.save();
    ctx.font = `800 ${fontSize}px Unbounded, Rubik, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    ctx.lineWidth = 4;
    ctx.strokeStyle = colors.secondary;
    ctx.strokeText(label, width / 2, 18);
    ctx.fillStyle = colors.main;
    ctx.fillText(label, width / 2, 18);
    ctx.restore();
  }
}
