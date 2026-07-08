import { COMBO_WINDOW_MS, HEAVY_DAMAGE } from "@/lib/hitEffects/store";
import type { FighterSide } from "@/lib/useHealth";

export interface BattleTracker {
  firstBloodAssigned: boolean;
  playerFirstBlood: boolean;
  playerCombo: { count: number; lastHitAt: number } | null;
  maxPlayerCombo: number;
  maxPlayerHitDealt: number;
  playerDamageTaken: number;
  playerKnockoutWin: boolean;
}

export function createBattleTracker(): BattleTracker {
  return {
    firstBloodAssigned: false,
    playerFirstBlood: false,
    playerCombo: null,
    maxPlayerCombo: 0,
    maxPlayerHitDealt: 0,
    playerDamageTaken: 0,
    playerKnockoutWin: false,
  };
}

export function recordBattleHit(
  tracker: BattleTracker,
  aggressorSide: FighterSide,
  damage: number,
  now: number,
): void {
  if (damage <= 0.5) return;

  if (!tracker.firstBloodAssigned) {
    tracker.firstBloodAssigned = true;
    tracker.playerFirstBlood = aggressorSide === "player";
  }

  if (aggressorSide === "player") {
    tracker.maxPlayerHitDealt = Math.max(tracker.maxPlayerHitDealt, damage);

    if (
      tracker.playerCombo &&
      now - tracker.playerCombo.lastHitAt <= COMBO_WINDOW_MS
    ) {
      tracker.playerCombo.count += 1;
    } else {
      tracker.playerCombo = { count: 1, lastHitAt: now };
    }
    tracker.maxPlayerCombo = Math.max(
      tracker.maxPlayerCombo,
      tracker.playerCombo.count,
    );
  } else {
    tracker.playerDamageTaken += damage;
  }
}

export function recordPlayerKnockoutWin(tracker: BattleTracker): void {
  tracker.playerKnockoutWin = true;
}

export const BRUTAL_HIT_DAMAGE = 50;
export { HEAVY_DAMAGE };
