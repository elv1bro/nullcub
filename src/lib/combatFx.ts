import type { Bounds } from "matter-js";
import type { DamageResult } from "./combat";
import type { FighterColors } from "./fighterColors";

export interface CombatFxConfig {
  playerCompositeId?: number;
  opponentCompositeId?: number;
  playerColors: FighterColors;
  opponentColors: FighterColors;
}

export function colorsForCompositeId(
  config: CombatFxConfig,
  compositeId: number,
): FighterColors | null {
  if (compositeId === config.playerCompositeId) return config.playerColors;
  if (compositeId === config.opponentCompositeId) return config.opponentColors;
  return null;
}

export interface HitParty {
  victimCompositeId: number;
  aggressorCompositeId: number;
  victimColors: FighterColors;
  aggressorColors: FighterColors;
  victimDamage: number;
}

export function resolveHitParties(
  result: DamageResult,
  compositeA: number,
  compositeB: number,
  config: CombatFxConfig,
): HitParty[] {
  const parties: HitParty[] = [];

  const push = (
    victimId: number,
    aggressorId: number,
    damage: number,
  ): void => {
    if (damage <= 0.5) return;
    const victimColors = colorsForCompositeId(config, victimId);
    const aggressorColors = colorsForCompositeId(config, aggressorId);
    if (!victimColors || !aggressorColors) return;
    parties.push({
      victimCompositeId: victimId,
      aggressorCompositeId: aggressorId,
      victimColors,
      aggressorColors,
      victimDamage: damage,
    });
  };

  if (result.victim === "b") push(compositeB, compositeA, result.damageB);
  else if (result.victim === "a") push(compositeA, compositeB, result.damageA);
  else if (result.victim === "both") {
    push(compositeA, compositeB, result.damageA);
    push(compositeB, compositeA, result.damageB);
  }

  return parties;
}

/** Скорость попапа: случайно, но не вылетает за край арены. */
export function safePopupVelocity(
  slot: number,
  x: number,
  y: number,
  bounds: Bounds,
): { vx: number; vy: number } {
  const dirs = [
    { vx: -22, vy: 2 },
    { vx: 22, vy: 2 },
    { vx: -16, vy: 12 },
    { vx: 16, vy: 12 },
    { vx: -6, vy: 18 },
    { vx: 6, vy: 18 },
  ];
  const base = dirs[slot % dirs.length]!;

  const cx = (bounds.min.x + bounds.max.x) / 2;
  const cy = (bounds.min.y + bounds.max.y) / 2;
  const dx = cx - x;
  const dy = cy - y;
  const halfW = (bounds.max.x - bounds.min.x) / 2;
  const halfH = (bounds.max.y - bounds.min.y) / 2;
  const edge = Math.max(
    Math.abs(x - cx) / halfW,
    Math.abs(y - cy) / halfH,
  );
  const pull = Math.min(0.85, Math.max(0, edge - 0.35) * 1.4);
  const len = Math.hypot(dx, dy) || 1;

  return {
    vx: base.vx * (1 - pull) + (dx / len) * 20 * pull,
    vy: base.vy * (1 - pull) + (dy / len) * 14 * pull,
  };
}

export function clampWorldPoint(
  point: { x: number; y: number },
  bounds: Bounds,
  margin = 36,
): { x: number; y: number } {
  return {
    x: Math.min(bounds.max.x - margin, Math.max(bounds.min.x + margin, point.x)),
    y: Math.min(bounds.max.y - margin, Math.max(bounds.min.y + margin, point.y)),
  };
}
