import { BATTLE_SPAWN_GRACE_MS } from "./battleTuning";

export function isBattleSpawnGrace(
  battleStartMs: number,
  now = performance.now(),
  graceMs = BATTLE_SPAWN_GRACE_MS,
): boolean {
  return battleStartMs > 0 && now - battleStartMs < graceMs;
}
