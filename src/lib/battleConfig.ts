/** Конфиг текущего боя — задаётся меню/мастерской до входа в арену. */

export type BattleConfig =
  | { kind: "quick" }
  | { kind: "local2p" }
  | { kind: "local4ffa"; humans: number }
  | { kind: "network"; roomId: string; role: "host" | "guest" }
  | { kind: "dedicated"; wsUrl: string; roomId: string; role: "host" | "guest" }
  | { kind: "campaign"; chapterId: string }
  | { kind: "monster"; monsterId: string };

export type BattleResult = {
  winner: "player" | "opponent" | "draw";
  config: BattleConfig;
};

let currentConfig: BattleConfig = { kind: "quick" };
let lastResult: BattleResult | null = null;

export function getBattleConfig(): BattleConfig {
  return currentConfig;
}

export function setBattleConfig(config: BattleConfig): void {
  currentConfig = config;
  lastResult = null;
}

export function setBattleQuick(): void {
  setBattleConfig({ kind: "quick" });
}

export function setBattleLocal2P(): void {
  setBattleConfig({ kind: "local2p" });
}

export function setBattleLocal4FFA(): void {
  setBattleConfig({ kind: "local4ffa", humans: 2 });
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
