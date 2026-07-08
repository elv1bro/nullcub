import { MAX_HP } from "@/lib/combat";
import type { BattleConfig } from "@/lib/battleConfig";
import type { MedalId } from "./medals";
import { MEDALS } from "./medals";
import {
  BRUTAL_HIT_DAMAGE,
  HEAVY_DAMAGE,
  type BattleTracker,
} from "./battleTracker";
import type { FighterSide } from "@/lib/useHealth";

const CLUTCH_HP_RATIO = 0.25;
const REVENGE_LOSS_STREAK = 2;

export interface BattleMedalContext {
  battleConfig?: BattleConfig;
  lossStreakBeforeBattle?: number;
}

export function evaluateBattleMedals(
  tracker: BattleTracker,
  winner: FighterSide | "draw",
  playerHp: number,
  maxHp: number = MAX_HP,
  context: BattleMedalContext = {},
): MedalId[] {
  const earned = new Set<MedalId>();

  if (tracker.playerFirstBlood) earned.add("first_blood");
  if (tracker.maxPlayerCombo >= 3) earned.add("combo_3");
  if (tracker.maxPlayerCombo >= 5) earned.add("combo_5");
  if (tracker.maxPlayerHitDealt >= HEAVY_DAMAGE) earned.add("heavy_hit");
  if (tracker.maxPlayerHitDealt >= BRUTAL_HIT_DAMAGE) earned.add("brutal_hit");

  if (winner === "player") {
    earned.add("victory");
    if (tracker.playerKnockoutWin) earned.add("knockout");
    if (playerHp > 0 && playerHp / maxHp <= CLUTCH_HP_RATIO) {
      earned.add("clutch");
    }
    if (tracker.playerDamageTaken <= 0.5) earned.add("flawless");
    if ((context.lossStreakBeforeBattle ?? 0) >= REVENGE_LOSS_STREAK) {
      earned.add("revenge");
    }
    if (context.battleConfig?.kind === "campaign") earned.add("bouncer");
    if (context.battleConfig?.kind === "monster") earned.add("workshop");
  }

  return MEDALS.map((m) => m.id).filter((id) => earned.has(id));
}
