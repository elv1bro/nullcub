import type Matter from "matter-js";
import {
  POPUP_LIFE_MS,
  popupAtTime,
  type HitPopup,
} from "@/lib/hitPopups";
import { renderCssSize, worldToCanvas } from "./worldToCanvas";

/** Минус-сердца — склеиваются, пульсируют, не уходят за экран. */
export function drawHitPopup(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  popup: HitPopup,
  now: number,
): void {
  const age = now - popup.born;
  if (age > POPUP_LIFE_MS) return;

  const fadeStart = POPUP_LIFE_MS - 500;
  const alpha =
    age < fadeStart ? 1 : Math.max(0, (POPUP_LIFE_MS - age) / (POPUP_LIFE_MS - fadeStart));
  const popIn = 1 + Math.sin(Math.min(age / 200, 1) * Math.PI) * 0.15;
  const stackScale = 1 + popup.pulse * 0.4 + Math.min(popup.hits - 1, 6) * 0.04;

  const pos = popupAtTime(popup, age, render.bounds);
  const { x, y, scale } = worldToCanvas(render, pos);

  const { width, height } = renderCssSize(render);
  const margin = 28;
  const cx = Math.min(width - margin, Math.max(margin, x));
  const cy = Math.min(height - margin, Math.max(margin, y));

  const fontSize = Math.max(14, 22 * scale) * popIn * stackScale;

  ctx.save();
  ctx.translate(cx, cy);
  ctx.globalAlpha = alpha;
  ctx.font = `900 ${fontSize}px Anton, Impact, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.lineWidth = Math.max(2.5, fontSize * 0.12);
  ctx.strokeStyle = popup.secondary;
  ctx.strokeText(popup.text, 0, 0);
  ctx.fillStyle = popup.color;
  ctx.fillText(popup.text, 0, 0);

  if (popup.hits > 1) {
    ctx.font = `700 ${Math.max(8, fontSize * 0.32)}px system-ui, sans-serif`;
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.fillText(`×${popup.hits}`, fontSize * 0.55, -fontSize * 0.42);
  }

  ctx.restore();
}
