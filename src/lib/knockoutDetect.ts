/** После applyDamage: был ли этот удар смертельным. */
export function isKnockoutFromLethalHit(
  hpAfterHit: number,
  hitDamage: number,
): boolean {
  return hpAfterHit <= 0 && hpAfterHit + hitDamage > 0.5;
}
