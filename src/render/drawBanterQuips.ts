import type Matter from "matter-js";
import {
  BANTER_LIFE_MS,
  banterAtTime,
  type BanterQuip,
} from "@/lib/banterQuips";
import { worldToCanvas } from "./worldToCanvas";

/** Комик-фразы рядом с бойцами — летят и крутятся. */
export function drawBanterQuips(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  quips: BanterQuip[],
  now: number,
): void {
  for (const quip of quips) {
    const age = now - quip.born;
    if (age > BANTER_LIFE_MS) continue;

    const t = age / BANTER_LIFE_MS;
    const alpha = (1 - t * t) * 0.92;
    const motion = banterAtTime(quip, age, render.bounds);
    const { x, y, scale: canvasScale } = worldToCanvas(render, motion);

    const fontSize =
      Math.max(13, 17 * motion.scale) *
      canvasScale *
      (0.9 + Math.min(quip.text.length / 30, 0.4));

    const fill = quip.color;
    const stroke = quip.secondary;

    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(motion.rotation);
    ctx.globalAlpha = alpha;

    ctx.fillStyle = "rgba(0,0,0,0.45)";
    ctx.beginPath();
    const padX = fontSize * 0.45;
    const padY = fontSize * 0.35;
    const w = fontSize * quip.text.length * 0.52 + padX * 2;
    const h = fontSize + padY * 2;
    ctx.roundRect(-w / 2, -h / 2, w, h, fontSize * 0.25);
    ctx.fill();

    ctx.font = `700 ${fontSize}px Rubik, Unbounded, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineWidth = Math.max(2, fontSize * 0.1);
    ctx.strokeStyle = stroke;
    ctx.strokeText(quip.text, 0, 0);
    ctx.fillStyle = fill;
    ctx.fillText(quip.text, 0, 0);

    ctx.restore();
  }
}
