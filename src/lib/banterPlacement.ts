import type { Body, Bounds } from "matter-js";
import type { BanterQuip } from "./banterQuips";
import { clampWorldPoint } from "./combatFx";

export function estimateBanterBubbleRadius(text: string, scale = 1): number {
  const fontSize =
    Math.max(13, 17 * scale) * (0.9 + Math.min(text.length / 30, 0.4));
  const padX = fontSize * 0.45;
  const padY = fontSize * 0.35;
  const w = fontSize * text.length * 0.52 + padX * 2;
  const h = fontSize + padY * 2;
  return Math.hypot(w, h) * 0.52;
}

function overlapsCircle(
  x: number,
  y: number,
  radius: number,
  cx: number,
  cy: number,
  cr: number,
): boolean {
  const dx = x - cx;
  const dy = y - cy;
  const min = radius + cr + 6;
  return dx * dx + dy * dy < min * min;
}

/** Ищет пустое место рядом с головой говорящего, в сторону от центра арены. */
export function findBanterSpot(
  headX: number,
  headY: number,
  side: "player" | "opponent",
  text: string,
  bounds: Bounds,
  bodies: Body[],
  existing: BanterQuip[],
  quipScale = 0.9,
): { x: number; y: number } {
  const bubbleR = estimateBanterBubbleRadius(text, quipScale);
  const away = side === "player" ? -1 : 1;
  const baseAngles = [
    -Math.PI / 2,
    -Math.PI / 2 + away * 0.55,
    -Math.PI / 2 - away * 0.55,
    -Math.PI / 2 + away * 0.95,
    -Math.PI / 2 - away * 0.35,
  ];
  const distances = [48, 62, 76, 90, 104, 118];

  let best: { x: number; y: number; score: number } | null = null;

  for (const dist of distances) {
    for (const angle of baseAngles) {
      const jitter = ((text.length + dist) % 7) * 0.015;
      const point = clampWorldPoint(
        {
          x: headX + Math.cos(angle + jitter) * dist * (0.92 + Math.abs(away) * 0.04),
          y: headY + Math.sin(angle + jitter) * dist - 18,
        },
        bounds,
        bubbleR + 24,
      );

      let score = dist * 0.15;

      for (const body of bodies) {
        const r = body.circleRadius ?? 12;
        if (overlapsCircle(point.x, point.y, bubbleR, body.position.x, body.position.y, r)) {
          score += 120;
        }
      }

      for (const quip of existing) {
        const quipR = estimateBanterBubbleRadius(quip.text, quip.scale);
        if (overlapsCircle(point.x, point.y, bubbleR, quip.x, quip.y, quipR)) {
          score += 250;
        }
      }

      const edgeX = Math.min(
        point.x - bounds.min.x,
        bounds.max.x - point.x,
      );
      const edgeY = Math.min(
        point.y - bounds.min.y,
        bounds.max.y - point.y,
      );
      if (edgeX < bubbleR + 8 || edgeY < bubbleR + 8) score += 60;

      if (!best || score < best.score) {
        best = { x: point.x, y: point.y, score: score };
      }
    }
  }

  if (best && best.score < 100) {
    return { x: best.x, y: best.y };
  }

  return clampWorldPoint(
    {
      x: headX + away * (bubbleR + 36),
      y: headY - bubbleR - 28,
    },
    bounds,
    bubbleR + 20,
  );
}
