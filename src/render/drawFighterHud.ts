import type Matter from "matter-js";
import { worldToCanvas } from "./worldToCanvas";

export interface FighterHudInfo {
  name: string;
  hearts: number;
  maxHearts?: number;
  colors: { main: string; secondary: string };
  side: "left" | "right";
}

/** Компактный unit-HUD над головой: имя, полоска HP, направление «взгляда». */
export function drawFighterHud(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  head: Matter.Body,
  info: FighterHudInfo,
): void {
  const radius = head.circleRadius ?? 20;
  const anchor = {
    x: head.position.x,
    y: head.position.y - radius * 2.45,
  };

  const { x, y, scale } = worldToCanvas(render, anchor);
  const nameSize = Math.max(9, 11 * scale);
  const padX = 7 * scale;
  const padY = 5 * scale;
  const barH = Math.max(5, 6.5 * scale);
  const barW = Math.max(48, 64 * scale);
  const hearts = Math.max(0, info.hearts);
  const maxHearts = Math.max(1, info.maxHearts ?? 1000);
  const ratio = Math.max(0, Math.min(1, hearts / maxHearts));
  const nameText = info.name.toUpperCase();

  ctx.save();
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = `800 ${nameSize}px Unbounded, system-ui, sans-serif`;
  const nameW = ctx.measureText(nameText).width;

  const boxW = Math.max(nameW, barW) + padX * 2;
  const boxH = nameSize + barH + padY * 2.4 + 2 * scale;

  ctx.fillStyle = "rgba(8, 6, 10, 0.55)";
  ctx.strokeStyle = "rgba(255, 248, 239, 0.18)";
  ctx.lineWidth = Math.max(1, 1.2 * scale);
  ctx.beginPath();
  ctx.roundRect(x - boxW / 2, y - boxH / 2, boxW, boxH, 5 * scale);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = "rgba(255,248,239,0.92)";
  ctx.fillText(nameText, x, y - boxH / 2 + padY + nameSize * 0.45);

  const barX = x - barW / 2;
  const barY = y + boxH / 2 - padY - barH;
  ctx.fillStyle = "rgba(0,0,0,0.55)";
  ctx.beginPath();
  ctx.roundRect(barX, barY, barW, barH, 2 * scale);
  ctx.fill();

  const fillW = Math.max(0, barW * ratio);
  if (fillW > 0) {
    const grad = ctx.createLinearGradient(barX, 0, barX + barW, 0);
    grad.addColorStop(0, info.colors.secondary);
    grad.addColorStop(1, info.colors.main);
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.roundRect(barX, barY, fillW, barH, 2 * scale);
    ctx.fill();
  }

  ctx.strokeStyle = "rgba(255,255,255,0.22)";
  ctx.lineWidth = Math.max(0.8, scale);
  ctx.beginPath();
  ctx.roundRect(barX, barY, barW, barH, 2 * scale);
  ctx.stroke();
  ctx.restore();

  // «взгляд» / aim — кольцо + шеврон по скорости головы
  const vx = head.velocity?.x ?? 0;
  const vy = head.velocity?.y ?? 0;
  const speed = Math.hypot(vx, vy);
  if (speed <= 0.35) return;

  const headCanvas = worldToCanvas(render, head.position);
  const ang = Math.atan2(vy, vx);
  const r = (radius + 10) * headCanvas.scale;
  const tipX = headCanvas.x + Math.cos(ang) * r;
  const tipY = headCanvas.y + Math.sin(ang) * r;
  const side = 7 * headCanvas.scale;

  ctx.save();
  ctx.globalAlpha = Math.min(0.55, 0.2 + speed * 0.05);
  ctx.strokeStyle = info.colors.main;
  ctx.lineWidth = Math.max(1.2, 1.5 * headCanvas.scale);
  ctx.beginPath();
  ctx.arc(
    headCanvas.x,
    headCanvas.y,
    (radius + 4) * headCanvas.scale,
    0,
    Math.PI * 2,
  );
  ctx.stroke();

  ctx.globalAlpha = Math.min(0.95, 0.35 + speed * 0.08);
  ctx.translate(tipX, tipY);
  ctx.rotate(ang);
  ctx.fillStyle = info.colors.main;
  ctx.beginPath();
  ctx.moveTo(side * 1.1, 0);
  ctx.lineTo(-side * 0.7, side * 0.7);
  ctx.lineTo(-side * 0.35, 0);
  ctx.lineTo(-side * 0.7, -side * 0.7);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}
