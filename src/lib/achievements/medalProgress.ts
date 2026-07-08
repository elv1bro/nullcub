import type { MedalId } from "./medals";
import type { PlayerStats } from "./store";

const REVENGE_TARGET = 2;

/** Прогресс к первому получению медали (0–1). */
export function getMedalProgress(
  stats: PlayerStats,
  id: MedalId,
): { current: number; target: number } {
  if ((stats.medals[id] ?? 0) > 0) {
    return { current: 1, target: 1 };
  }

  switch (id) {
    case "revenge":
      return {
        current: Math.min(stats.lossStreak, REVENGE_TARGET),
        target: REVENGE_TARGET,
      };
    case "victory":
      return { current: stats.wins > 0 ? 1 : 0, target: 1 };
    default:
      return { current: 0, target: 1 };
  }
}

export function medalProgressRatio(
  stats: PlayerStats,
  id: MedalId,
): number {
  const { current, target } = getMedalProgress(stats, id);
  if (target <= 0) return 0;
  return Math.min(1, current / target);
}
