import type { BattleConfig } from "@/lib/battleConfig";
import {
  setBattleLocal2P,
  setBattleLocal4FFA,
  setBattleNetwork,
  setBattleQuick,
} from "@/lib/battleConfig";

export const TEAM_SIZE = 4;

export type TeamSlotIndex = 1 | 2 | 3 | 4;

export type TeamSlot =
  | { kind: "you"; name: string }
  | { kind: "empty" }
  | { kind: "local"; name: string; seat: 2 | 3 | 4 }
  | { kind: "remote"; peerId: string; name: string };

export interface TeamLobbySnapshot {
  slots: TeamSlot[];
  remoteCount: number;
  localHumanCount: number;
  roomId: string | null;
  isHost: boolean;
}

export function countLocalHumans(slots: TeamSlot[]): number {
  return slots.filter((s) => s.kind === "you" || s.kind === "local").length;
}

export function countRemote(slots: TeamSlot[]): number {
  return slots.filter((s) => s.kind === "remote").length;
}

/** Выбор battleConfig по составу команды. */
export function applyTeamBattleConfig(
  snapshot: TeamLobbySnapshot,
): BattleConfig {
  const remote = snapshot.remoteCount;
  const locals = snapshot.localHumanCount;

  if (remote > 0) {
    if (!snapshot.roomId) throw new Error("team: missing roomId");
    setBattleNetwork(snapshot.roomId, snapshot.isHost ? "host" : "guest");
    return { kind: "network", roomId: snapshot.roomId, role: snapshot.isHost ? "host" : "guest" };
  }
  if (locals >= 3) {
    setBattleLocal4FFA();
    return { kind: "local4ffa", humans: locals };
  }
  if (locals === 2) {
    setBattleLocal2P();
    return { kind: "local2p" };
  }
  setBattleQuick();
  return { kind: "quick" };
}

export function emptyExtraSlots(): Record<2 | 3 | 4, TeamSlot> {
  return {
    2: { kind: "empty" },
    3: { kind: "empty" },
    4: { kind: "empty" },
  };
}
