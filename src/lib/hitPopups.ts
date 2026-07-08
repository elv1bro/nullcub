import type { Bounds } from "matter-js";
import { clampWorldPoint, safePopupVelocity } from "./combatFx";

export interface HitPopup {
  text: string;
  damage: number;
  hits: number;
  /** Ключ жертвы для склейки ударов */
  victimKey: string;
  x: number;
  y: number;
  born: number;
  lastStackAt: number;
  /** Пульс при склейке (0–1, затухает) */
  pulse: number;
  vx: number;
  vy: number;
  color: string;
  secondary: string;
}

export const POPUP_LIFE_MS = 3000;
export const POPUP_MERGE_MS = 1000;

const GRAVITY = 22;

export function prunePopups(popups: HitPopup[], now: number): HitPopup[] {
  return popups.filter((p) => now - p.born < POPUP_LIFE_MS);
}

export function popupAtTime(
  popup: HitPopup,
  ageMs: number,
  bounds?: Bounds,
): { x: number; y: number } {
  const sec = ageMs / 1000;
  const drag = Math.max(0.35, 1 - sec * 0.18);

  let x = popup.x + popup.vx * sec * drag;
  let y = popup.y + popup.vy * sec * drag + GRAVITY * sec * sec;

  if (bounds) {
    ({ x, y } = clampWorldPoint({ x, y }, bounds, 48));
  }

  return { x, y };
}

export function decayPopupPulse(popups: HitPopup[]): void {
  for (const p of popups) {
    if (p.pulse > 0) p.pulse = Math.max(0, p.pulse - 0.06);
  }
}

export function findMergePopup(
  popups: HitPopup[],
  victimKey: string,
  now: number,
): HitPopup | undefined {
  return popups.find(
    (p) =>
      p.victimKey === victimKey && now - p.lastStackAt < POPUP_MERGE_MS,
  );
}

export function createPopup(
  damage: number,
  damageText: string,
  x: number,
  y: number,
  now: number,
  victimKey: string,
  colors: { main: string; secondary: string },
  slot: number,
  bounds: Bounds,
): HitPopup {
  const impulse = safePopupVelocity(slot, x, y, bounds);
  return {
    text: damageText,
    damage,
    hits: 1,
    victimKey,
    x,
    y,
    born: now,
    lastStackAt: now,
    pulse: 0.85,
    ...impulse,
    color: colors.main,
    secondary: colors.secondary,
  };
}

export function stackPopup(
  popup: HitPopup,
  damage: number,
  formatDamage: (total: number) => string,
  now: number,
): void {
  popup.damage += damage;
  popup.hits += 1;
  popup.text = formatDamage(popup.damage);
  popup.lastStackAt = now;
  popup.pulse = Math.min(1, popup.pulse + 0.55);
}
