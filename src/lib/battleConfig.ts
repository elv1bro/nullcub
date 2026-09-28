/** Конфиг текущего боя — задаётся меню/мастерской до входа в арену. */

import type {
  AbilityId,
  FighterLoadout,
  PassiveItemId,
} from "@/loadout/types";
import type { RoguelikeDifficulty } from "@/roguelike/runState";

/** HP бота в стандартном режиме «против бота». */
export const QUICK_OPPONENT_HP_OPTIONS = [1, 100, 1000, 5000, 10000] as const;
export type QuickOpponentHp = (typeof QUICK_OPPONENT_HP_OPTIONS)[number];
export const QUICK_OPPONENT_HP_DEFAULT: QuickOpponentHp = 1000;

export function clampQuickOpponentHp(hp: number): QuickOpponentHp {
  const n = Math.round(hp);
  if ((QUICK_OPPONENT_HP_OPTIONS as readonly number[]).includes(n)) {
    return n as QuickOpponentHp;
  }
  // Ближайшее из пресетов.
  let best: QuickOpponentHp = QUICK_OPPONENT_HP_DEFAULT;
  let bestDist = Infinity;
  for (const opt of QUICK_OPPONENT_HP_OPTIONS) {
    const d = Math.abs(opt - n);
    if (d < bestDist) {
      best = opt;
      bestDist = d;
    }
  }
  return best;
}

export type BattleConfig =
  | { kind: "quick"; opponentHp?: QuickOpponentHp }
  | { kind: "local2p" }
  | { kind: "local4ffa"; humans: number }
  | {
      kind: "teamBots";
      /** Локальные люди в команде 0 (1–4; управление — первые 2). */
      humans: number;
      humanNames: string[];
      /** Боты в команде 1. */
      bots: number;
      difficulty: RoguelikeDifficulty;
    }
  | { kind: "network"; roomId: string; role: "host" | "guest" }
  | { kind: "dedicated"; wsUrl: string; roomId: string; role: "host" | "guest" }
  | { kind: "campaign"; chapterId: string }
  | { kind: "monster"; monsterId: string }
  | {
      kind: "roguelike";
      floor: number;
      bots: number;
      difficulty: RoguelikeDifficulty;
      loadouts: Record<string, FighterLoadout>;
    }
  | {
      kind: "lab";
      /** Оружие на арене (обычно выбранное + дозаполнение). */
      arenaItemIds: string[];
      loadout: FighterLoadout;
    }
  | {
      kind: "testArena";
      playerHp: number;
      opponentHp: number;
      opponentCount: number;
      arenaItemIds: string[];
      loadout: FighterLoadout;
      extraItems: PassiveItemId[];
      castAbilities: AbilityId[];
    }
  | {
      kind: "weaponSandbox";
      arenaItemIds: string[];
    };

export type BattleResult = {
  winner: "player" | "opponent" | "draw";
  config: BattleConfig;
};

let currentConfig: BattleConfig = {
  kind: "quick",
  opponentHp: QUICK_OPPONENT_HP_DEFAULT,
};
let lastResult: BattleResult | null = null;

export function getBattleConfig(): BattleConfig {
  return currentConfig;
}

export function setBattleConfig(config: BattleConfig): void {
  currentConfig = config;
  lastResult = null;
}

export function setBattleQuick(opts?: { opponentHp?: number }): void {
  setBattleConfig({
    kind: "quick",
    opponentHp: clampQuickOpponentHp(
      opts?.opponentHp ?? QUICK_OPPONENT_HP_DEFAULT,
    ),
  });
}

export function setBattleLocal2P(): void {
  setBattleConfig({ kind: "local2p" });
}

export function setBattleLocal4FFA(): void {
  setBattleConfig({ kind: "local4ffa", humans: 2 });
}

export function setBattleTeamBots(opts: {
  humans: number;
  humanNames: string[];
  bots?: number;
  difficulty?: RoguelikeDifficulty;
}): void {
  setBattleConfig({
    kind: "teamBots",
    humans: Math.max(1, Math.min(4, opts.humans)),
    humanNames: opts.humanNames.slice(0, 4),
    bots: Math.max(1, Math.min(3, opts.bots ?? 1)),
    difficulty: opts.difficulty ?? "normal",
  });
}

export function setBattleNetwork(roomId: string, role: "host" | "guest"): void {
  setBattleConfig({ kind: "network", roomId, role });
}

export function setBattleDedicated(
  wsUrl: string,
  roomId: string,
  role: "host" | "guest",
): void {
  setBattleConfig({ kind: "dedicated", wsUrl, roomId, role });
}

export function setBattleRoguelike(opts: {
  floor: number;
  bots: number;
  difficulty: RoguelikeDifficulty;
  loadouts: Record<string, FighterLoadout>;
}): void {
  setBattleConfig({ kind: "roguelike", ...opts });
}

export function setBattleLab(opts: {
  arenaItemIds: string[];
  loadout: FighterLoadout;
}): void {
  setBattleConfig({
    kind: "lab",
    arenaItemIds: opts.arenaItemIds.slice(0, 8),
    loadout: opts.loadout,
  });
}

export function setBattleTestArena(opts: {
  playerHp: number;
  opponentHp: number;
  opponentCount: number;
  arenaItemIds: string[];
  loadout: FighterLoadout;
  extraItems: PassiveItemId[];
  castAbilities: AbilityId[];
}): void {
  setBattleConfig({
    kind: "testArena",
    playerHp: Math.max(50, Math.min(5000, Math.round(opts.playerHp))),
    opponentHp: Math.max(50, Math.min(5000, Math.round(opts.opponentHp))),
    opponentCount: Math.max(1, Math.min(4, Math.round(opts.opponentCount))),
    arenaItemIds: opts.arenaItemIds.slice(0, 8),
    loadout: opts.loadout,
    extraItems: opts.extraItems.slice(0, 8),
    castAbilities: opts.castAbilities.slice(0, 8),
  });
}

export function setBattleWeaponSandbox(opts: {
  arenaItemIds: string[];
}): void {
  setBattleConfig({
    kind: "weaponSandbox",
    arenaItemIds: opts.arenaItemIds.slice(0, 8),
  });
}

export function setBattleResult(result: BattleResult): void {
  lastResult = result;
}

export function peekBattleResult(): BattleResult | null {
  return lastResult;
}

export function consumeBattleResult(): BattleResult | null {
  const result = lastResult;
  lastResult = null;
  return result;
}
