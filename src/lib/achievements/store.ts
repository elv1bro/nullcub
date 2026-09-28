import type { BattleConfig } from "@/lib/battleConfig";
import type { FighterSide } from "@/lib/useHealth";
import {
  createBattleTracker,
  type BattleTracker,
} from "./battleTracker";
import { evaluateBattleMedals } from "./evaluate";
import type { MedalId } from "./medals";
import { scheduleCloudPush } from "@/cloud/schedulePush";
import { loadVersioned, saveVersioned } from "@/lib/storageSchema";

export interface PlayerStats {
  battles: number;
  wins: number;
  losses: number;
  lossStreak: number;
  medals: Partial<Record<MedalId, number>>;
}

const STORAGE_KEY = "ragdoll-faces-stats";
const SCHEMA_VERSION = 1;

export const DEFAULT_PLAYER_STATS: PlayerStats = {
  battles: 0,
  wins: 0,
  losses: 0,
  lossStreak: 0,
  medals: {},
};

export function loadPlayerStats(): PlayerStats {
  return loadVersioned<PlayerStats>({
    key: STORAGE_KEY,
    version: SCHEMA_VERSION,
    migrate: (data) => {
      if (typeof data !== "object" || data === null) return null;
      const parsed = data as Partial<PlayerStats>;
      return {
        battles: parsed.battles ?? 0,
        wins: parsed.wins ?? 0,
        losses: parsed.losses ?? 0,
        lossStreak: parsed.lossStreak ?? 0,
        medals: parsed.medals ?? {},
      };
    },
    fallback: () => ({ ...DEFAULT_PLAYER_STATS, medals: {} }),
  });
}

export function replacePlayerStats(stats: PlayerStats): void {
  saveVersioned(STORAGE_KEY, SCHEMA_VERSION, stats);
}

function savePlayerStats(stats: PlayerStats): void {
  replacePlayerStats(stats);
}

export interface BattleEndResult {
  medals: MedalId[];
  stats: PlayerStats;
  lossStreakBeforeBattle: number;
}

export function recordBattleEnd(input: {
  tracker: BattleTracker;
  winner: FighterSide | "draw";
  playerHp: number;
  maxHp?: number;
  battleConfig?: BattleConfig;
}): BattleEndResult {
  const stats = loadPlayerStats();
  const lossStreakBeforeBattle = stats.lossStreak;

  const medals = evaluateBattleMedals(
    input.tracker,
    input.winner,
    input.playerHp,
    input.maxHp,
    {
      battleConfig: input.battleConfig,
      lossStreakBeforeBattle,
    },
  );

  stats.battles += 1;
  if (input.winner === "player") {
    stats.wins += 1;
    stats.lossStreak = 0;
  } else if (input.winner === "opponent") {
    stats.losses += 1;
    stats.lossStreak += 1;
  }
  // Ничья (двойной нокаут) — бой засчитан, серия поражений не растёт.

  for (const id of medals) {
    stats.medals[id] = (stats.medals[id] ?? 0) + 1;
  }

  savePlayerStats(stats);
  scheduleCloudPush();
  return { medals, stats, lossStreakBeforeBattle };
}

export { createBattleTracker, type BattleTracker };
