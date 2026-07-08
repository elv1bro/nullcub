import type { Composite } from "matter-js";
import { isKoScatteredId } from "./victoryKoScatter";

export type DamageTradeOpts = {
  battleOver: boolean;
  playerHp: number;
  opponentHp: number;
  playerCompositeId?: number;
  opponentCompositeId?: number;
};

/** Мёртвый боец не наносит урон (голова-призрак после KO). */
export function canCompositeDealDamage(
  aggressorCompositeId: number,
  opts: DamageTradeOpts,
): boolean {
  if (opts.playerCompositeId === aggressorCompositeId && opts.playerHp <= 0) {
    return false;
  }
  if (
    opts.opponentCompositeId === aggressorCompositeId &&
    opts.opponentHp <= 0
  ) {
    return false;
  }
  return true;
}

/** Обнуляет урон от мёртвых агрессоров. damageA — урон телу A от B, damageB — урон телу B от A. */
export function filterDamageFromDeadAggressors(
  compositeAId: number,
  compositeBId: number,
  damageA: number,
  damageB: number,
  opts: DamageTradeOpts,
): { damageA: number; damageB: number } {
  let nextA = damageA;
  let nextB = damageB;
  if (!canCompositeDealDamage(compositeBId, opts)) nextA = 0;
  if (!canCompositeDealDamage(compositeAId, opts)) nextB = 0;
  return { damageA: nextA, damageB: nextB };
}

/** Можно ли наносить урон между двумя ragdoll (не после KO / разлёта). */
export function canFightersTradeDamage(
  compositeAId: number,
  compositeBId: number,
  composites: Composite[],
  opts: DamageTradeOpts,
): boolean {
  if (opts.battleOver) return false;
  if (opts.playerHp <= 0 && opts.opponentHp <= 0) return false;
  if (isKoScatteredId(compositeAId, composites)) return false;
  if (isKoScatteredId(compositeBId, composites)) return false;

  const filtered = filterDamageFromDeadAggressors(
    compositeAId,
    compositeBId,
    1,
    1,
    opts,
  );
  return filtered.damageA > 0 || filtered.damageB > 0;
}
