import type { Bounds } from "matter-js";
import { clampWorldPoint } from "./combatFx";
import { findBanterSpot } from "./banterPlacement";

export interface BanterQuip {
  text: string;
  x: number;
  y: number;
  born: number;
  side: "player" | "opponent";
  color: string;
  secondary: string;
  vx: number;
  vy: number;
  rotation: number;
  spin: number;
  scale: number;
}

export const BANTER_LIFE_MS = 3200;

const GRAVITY = 18;
let lastPick = "";

export function pruneBanter(quips: BanterQuip[], now: number): BanterQuip[] {
  return quips.filter((q) => now - q.born < BANTER_LIFE_MS);
}

export function banterAtTime(
  quip: BanterQuip,
  ageMs: number,
  bounds?: Bounds,
): { x: number; y: number; rotation: number; scale: number } {
  const sec = ageMs / 1000;
  const drag = Math.max(0.35, 1 - sec * 0.15);

  let x = quip.x + quip.vx * sec * drag;
  let y = quip.y + quip.vy * sec * drag + GRAVITY * sec * sec;
  const rotation = quip.rotation + quip.spin * sec;

  const pop = 1 + Math.sin(Math.min(ageMs / 220, 1) * Math.PI) * 0.25;

  if (bounds) {
    ({ x, y } = clampWorldPoint({ x, y }, bounds, 56));
  }

  return { x, y, rotation, scale: quip.scale * pop };
}

/** Случайная фраза рядом с головой говорящего. */
export function pickBanter(
  text: string,
  side: "player" | "opponent",
  anchorX: number,
  anchorY: number,
  slot: number,
  now: number,
  colors: { main: string; secondary: string },
  placement?: {
    bounds: Bounds;
    bodies: import("matter-js").Body[];
    existing: BanterQuip[];
  },
): BanterQuip {
  if (!text) {
    return {
      text: "…",
      x: anchorX,
      y: anchorY,
      born: now,
      side,
      color: colors.main,
      secondary: colors.secondary,
      vx: 0,
      vy: -8,
      rotation: 0,
      spin: 0,
      scale: 1,
    };
  }

  let line = text;
  if (line === lastPick) {
    line = `${text}…`;
  }
  lastPick = text;

  const scale = 0.85 + Math.min(line.length / 40, 0.35);
  const spot = placement
    ? findBanterSpot(
        anchorX,
        anchorY,
        side,
        line,
        placement.bounds,
        placement.bodies,
        placement.existing,
        scale,
      )
    : { x: anchorX, y: anchorY - 12 };

  const away = side === "player" ? -1 : 1;
  const angle =
    (away > 0 ? 0 : Math.PI) +
    (Math.random() - 0.5) * 0.7 +
    ((slot % 5) - 2) * 0.18;
  const speed = 10 + Math.random() * 12;

  return {
    text: line,
    x: spot.x + (Math.random() - 0.5) * 8,
    y: spot.y + (Math.random() - 0.5) * 6,
    born: now,
    side,
    color: colors.main,
    secondary: colors.secondary,
    vx: Math.cos(angle) * speed,
    vy: Math.sin(angle) * speed - 6,
    rotation: (Math.random() - 0.5) * 0.25,
    spin: (Math.random() - 0.5) * 0.45,
    scale,
  };
}
