import type { Language } from "@/i18n";

export type FaceOverlayEffectId =
  | "none"
  | "fire_eyes"
  | "laser_eyes"
  | "glitch"
  | "halo"
  | "demon";

export interface FaceOverlayEffectDef {
  id: FaceOverlayEffectId;
  icon: string;
  label: Record<Language, string>;
}

export const FACE_OVERLAY_EFFECTS: FaceOverlayEffectDef[] = [
  { id: "none", icon: "○", label: { en: "None", ru: "Без эффекта" } },
  { id: "fire_eyes", icon: "🔥", label: { en: "Fire eyes", ru: "Огненные глаза" } },
  { id: "laser_eyes", icon: "🔴", label: { en: "Laser", ru: "Лазер" } },
  { id: "glitch", icon: "📺", label: { en: "Glitch", ru: "Глитч" } },
  { id: "halo", icon: "✨", label: { en: "Halo", ru: "Ореол" } },
  { id: "demon", icon: "👁", label: { en: "Demon", ru: "Демон" } },
];

const EYE_Y = -0.12;
const EYE_X = 0.28;

function eyePos(r: number, side: -1 | 1): { x: number; y: number } {
  return { x: side * EYE_X * r, y: EYE_Y * r };
}

function drawFireEyes(
  ctx: CanvasRenderingContext2D,
  r: number,
  now: number,
): void {
  const flicker = 0.85 + Math.sin(now * 0.012) * 0.15;
  for (const side of [-1, 1] as const) {
    const { x, y } = eyePos(r, side);
    const glow = r * 0.22 * flicker;
    const grad = ctx.createRadialGradient(x, y, 0, x, y, glow);
    grad.addColorStop(0, "rgba(255, 240, 120, 0.95)");
    grad.addColorStop(0.35, "rgba(255, 120, 20, 0.75)");
    grad.addColorStop(1, "rgba(255, 40, 0, 0)");
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, glow, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = `rgba(255, 200, 60, ${0.55 + Math.sin(now * 0.02 + side) * 0.2})`;
    ctx.beginPath();
    ctx.arc(x, y, r * 0.07, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.strokeStyle = `rgba(255, 140, 0, ${0.35 + Math.sin(now * 0.015) * 0.15})`;
  ctx.lineWidth = r * 0.04;
  for (let i = 0; i < 3; i += 1) {
    const phase = now * 0.008 + i * 1.2;
    ctx.beginPath();
    ctx.moveTo(-r * 0.15, -r * 0.35 - Math.sin(phase) * r * 0.08);
    ctx.quadraticCurveTo(0, -r * 0.55, r * 0.15, -r * 0.32 - Math.cos(phase) * r * 0.06);
    ctx.stroke();
  }
}

function drawLaserEyes(ctx: CanvasRenderingContext2D, r: number, now: number): void {
  const pulse = 0.7 + Math.sin(now * 0.02) * 0.3;
  for (const side of [-1, 1] as const) {
    const { x, y } = eyePos(r, side);
    ctx.fillStyle = `rgba(255, 30, 30, ${pulse})`;
    ctx.beginPath();
    ctx.arc(x, y, r * 0.08, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = `rgba(255, 80, 80, ${0.5 * pulse})`;
    ctx.lineWidth = r * 0.05;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + side * r * 1.4, y + r * 0.05);
    ctx.stroke();

    ctx.strokeStyle = `rgba(255, 0, 0, ${0.85 * pulse})`;
    ctx.lineWidth = r * 0.025;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + side * r * 1.4, y + r * 0.05);
    ctx.stroke();
  }
}

function drawGlitch(ctx: CanvasRenderingContext2D, r: number, now: number): void {
  const bands = 6;
  for (let i = 0; i < bands; i += 1) {
    if (Math.sin(now * 0.03 + i * 2.1) < 0.2) continue;
    const y0 = -r * 0.85 + (i / bands) * r * 1.7;
    const h = r * 0.22;
    const shift = Math.sin(now * 0.04 + i) * r * 0.08;
    ctx.fillStyle =
      i % 3 === 0
        ? "rgba(0, 255, 255, 0.18)"
        : i % 3 === 1
          ? "rgba(255, 0, 128, 0.14)"
          : "rgba(255, 255, 0, 0.1)";
    ctx.fillRect(-r + shift, y0, r * 2, h);
  }
  ctx.strokeStyle = "rgba(255, 255, 255, 0.25)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(-r, 0);
  ctx.lineTo(r, 0);
  ctx.stroke();
}

function drawHalo(ctx: CanvasRenderingContext2D, r: number, now: number): void {
  const pulse = 0.75 + Math.sin(now * 0.006) * 0.25;
  ctx.strokeStyle = `rgba(255, 230, 140, ${0.55 * pulse})`;
  ctx.lineWidth = r * 0.07;
  ctx.beginPath();
  ctx.ellipse(0, -r * 0.72, r * 0.55, r * 0.12, 0, 0, Math.PI * 2);
  ctx.stroke();

  ctx.strokeStyle = `rgba(255, 255, 220, ${0.25 * pulse})`;
  ctx.lineWidth = r * 0.14;
  ctx.beginPath();
  ctx.ellipse(0, -r * 0.72, r * 0.62, r * 0.16, 0, 0, Math.PI * 2);
  ctx.stroke();
}

function drawDemon(ctx: CanvasRenderingContext2D, r: number, now: number): void {
  ctx.fillStyle = "rgba(0, 0, 0, 0.35)";
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.88, 0, Math.PI * 2);
  ctx.fill();

  const pulse = 0.8 + Math.sin(now * 0.018) * 0.2;
  for (const side of [-1, 1] as const) {
    const { x, y } = eyePos(r, side);
    const glow = r * 0.16;
    const grad = ctx.createRadialGradient(x, y, 0, x, y, glow);
    grad.addColorStop(0, `rgba(220, 80, 255, ${pulse})`);
    grad.addColorStop(0.5, `rgba(140, 0, 200, ${0.6 * pulse})`);
    grad.addColorStop(1, "rgba(80, 0, 120, 0)");
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, glow, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.ellipse(x, y, r * 0.045, r * 0.11, 0, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** Мини-превью эффекта для карусели в меню. */
export function drawFaceEffectPreview(
  ctx: CanvasRenderingContext2D,
  size: number,
  effect: FaceOverlayEffectId,
  now: number,
): void {
  ctx.clearRect(0, 0, size, size);
  const r = size * 0.38;
  ctx.save();
  ctx.translate(size / 2, size / 2);
  ctx.fillStyle = "#2a2a36";
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "rgba(255, 230, 210, 0.85)";
  ctx.beginPath();
  ctx.arc(0, r * 0.05, r * 0.55, 0, Math.PI * 2);
  ctx.fill();
  if (effect !== "none") {
    drawFaceOverlayEffect(ctx, r, effect, now);
  } else {
    ctx.strokeStyle = "rgba(255, 255, 255, 0.28)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, 0, r * 0.94, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.restore();
}

/** Эффекты поверх вебки / заглушки в локальных координатах головы. */
export function drawFaceOverlayEffect(
  ctx: CanvasRenderingContext2D,
  r: number,
  effect: FaceOverlayEffectId,
  now: number,
): void {
  switch (effect) {
    case "fire_eyes":
      drawFireEyes(ctx, r, now);
      break;
    case "laser_eyes":
      drawLaserEyes(ctx, r, now);
      break;
    case "glitch":
      drawGlitch(ctx, r, now);
      break;
    case "halo":
      drawHalo(ctx, r, now);
      break;
    case "demon":
      drawDemon(ctx, r, now);
      break;
    default:
      break;
  }
}
