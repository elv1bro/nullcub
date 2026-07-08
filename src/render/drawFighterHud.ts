import type Matter from "matter-js";
import { worldToCanvas } from "./worldToCanvas";

export interface FighterHudInfo {
  name: string;
  hearts: number;
  colors: { main: string; secondary: string };
  side: "left" | "right";
}

/** Компактная подпись над головой — всегда ровный экранный текст. */
export function drawFighterHud(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  head: Matter.Body,
  info: FighterHudInfo,
): void {
  const radius = head.circleRadius ?? 20;
  const anchor = {
    x: head.position.x,
    y: head.position.y - radius * 2.35,
  };

  const { x, y, scale } = worldToCanvas(render, anchor);
  const nameSize = Math.max(9, 10.5 * scale);
  const hpSize = Math.max(8, 9.5 * scale);
  const lineGap = nameSize * 1.05;
  const padX = 6 * scale;
  const padY = 4 * scale;
  const hearts = Math.ceil(info.hearts);
  const nameText = info.name.toUpperCase();
  const hpText = String(hearts);

  ctx.save();
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";

  ctx.font = `700 ${nameSize}px system-ui, sans-serif`;
  const nameW = ctx.measureText(nameText).width;

  ctx.font = `600 ${hpSize}px system-ui, sans-serif`;
  const hpW = hpSize * 1.5 + ctx.measureText(hpText).width;

  const boxW = Math.max(nameW, hpW) + padX * 2;
  const boxH = lineGap + hpSize + padY * 2;

  ctx.fillStyle = "rgba(0, 0, 0, 0.26)";
  ctx.beginPath();
  ctx.roundRect(x - boxW / 2, y - boxH / 2, boxW, boxH, 4 * scale);
  ctx.fill();

  ctx.font = `700 ${nameSize}px system-ui, sans-serif`;
  ctx.fillStyle = "rgba(255,255,255,0.82)";
  ctx.fillText(nameText, x, y - lineGap * 0.35);

  const rowY = y + lineGap * 0.45;
  const heartX = x - hpW / 2 + hpSize * 0.35;

  ctx.font = `${hpSize}px system-ui, sans-serif`;
  ctx.textAlign = "left";
  ctx.fillStyle = info.colors.main;
  ctx.fillText("♥", heartX, rowY);

  ctx.font = `600 ${hpSize}px system-ui, sans-serif`;
  ctx.fillStyle = "rgba(255,255,255,0.78)";
  ctx.fillText(hpText, heartX + hpSize * 0.9, rowY);

  ctx.restore();
}
