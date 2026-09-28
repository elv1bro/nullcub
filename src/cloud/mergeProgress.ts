import type { PlayerStats } from "@/lib/achievements/store";
import type { PlayerProfile } from "@/player/PlayerProfileContext";

/** Кампания: берём максимум открытых глав. */
export function mergeCampaignOrder(local: number, remote: number): number {
  return Math.max(0, local, remote);
}

/** Статы: max по счётчикам (не теряем локальный прогресс при первом логине). */
export function mergePlayerStats(
  local: PlayerStats,
  remote: PlayerStats,
): PlayerStats {
  const medalKeys = new Set([
    ...Object.keys(local.medals),
    ...Object.keys(remote.medals),
  ]);
  const medals: PlayerStats["medals"] = {};
  for (const key of medalKeys) {
    const id = key as keyof PlayerStats["medals"];
    medals[id] = Math.max(local.medals[id] ?? 0, remote.medals[id] ?? 0);
  }
  return {
    battles: Math.max(local.battles, remote.battles),
    wins: Math.max(local.wins, remote.wins),
    losses: Math.max(local.losses, remote.losses),
    lossStreak: Math.max(local.lossStreak, remote.lossStreak),
    medals,
  };
}

/**
 * Профиль: remote выигрывает по полям идентичности, если updated_at новее;
 * иначе оставляем local. Здесь сравниваем по флагу preferRemote.
 */
export function mergeProfile(
  local: PlayerProfile,
  remote: PlayerProfile,
  preferRemote: boolean,
): PlayerProfile {
  if (!preferRemote) return local;
  return {
    ...local,
    ...remote,
    colors: { ...remote.colors },
  };
}
