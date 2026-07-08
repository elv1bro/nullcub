export type { MedalId, MedalDef } from "./medals";
export { MEDALS, MEDAL_BY_ID } from "./medals";
export {
  createBattleTracker,
  recordBattleHit,
  recordPlayerKnockoutWin,
  type BattleTracker,
} from "./battleTracker";
export { evaluateBattleMedals } from "./evaluate";
export {
  loadPlayerStats,
  recordBattleEnd,
  DEFAULT_PLAYER_STATS,
  type PlayerStats,
  type BattleEndResult,
} from "./store";
