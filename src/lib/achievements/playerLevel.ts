import type { PlayerStats } from "./store";

/** XP / уровень — чисто производные от уже существующих статов (без новой БД). */
export interface PlayerLevelInfo {
  level: number;
  xp: number;
  xpIntoLevel: number;
  xpForNext: number;
  /** 0..1 прогресс внутри текущего уровня */
  progress: number;
  titleId: PlayerRankId;
}

export type PlayerRankId =
  | "rookie"
  | "brawler"
  | "slugger"
  | "contender"
  | "champion"
  | "legend";

const RANK_BY_LEVEL: { min: number; id: PlayerRankId }[] = [
  { min: 20, id: "legend" },
  { min: 14, id: "champion" },
  { min: 9, id: "contender" },
  { min: 5, id: "slugger" },
  { min: 2, id: "brawler" },
  { min: 1, id: "rookie" },
];

export function computePlayerXp(stats: PlayerStats): number {
  const medalTotal = Object.values(stats.medals).reduce(
    (sum, n) => sum + (n ?? 0),
    0,
  );
  const medalKinds = Object.values(stats.medals).filter((n) => (n ?? 0) > 0)
    .length;
  return (
    stats.wins * 25 +
    stats.battles * 5 +
    medalTotal * 12 +
    medalKinds * 8
  );
}

/** Сколько XP нужно, чтобы пройти уровень `level` → `level+1`. */
export function xpNeededForLevel(level: number): number {
  const safe = Math.max(1, Math.floor(level));
  return 40 + (safe - 1) * 18;
}

export function computePlayerLevel(stats: PlayerStats): PlayerLevelInfo {
  const xp = computePlayerXp(stats);
  let level = 1;
  let remaining = xp;
  let need = xpNeededForLevel(level);

  // Soft cap — не раздуваем UI огромными цифрами.
  while (remaining >= need && level < 50) {
    remaining -= need;
    level += 1;
    need = xpNeededForLevel(level);
  }

  const titleId =
    RANK_BY_LEVEL.find((r) => level >= r.min)?.id ?? "rookie";

  return {
    level,
    xp,
    xpIntoLevel: remaining,
    xpForNext: need,
    progress: need > 0 ? Math.min(1, remaining / need) : 1,
    titleId,
  };
}
