import type { AiProfile } from "@/battle/aiProfiles";
import type { Composite, Body } from "matter-js";
import type { FighterColors } from "@/lib/fighterColors";
import type { FighterGrabState } from "@/lib/grab/types";

export type FighterId = string;

export type FighterController =
  | "keyboard"
  | "keyboard2"
  | "gamepad"
  | "ai"
  | "remote";

export type BattleMode = "duel" | "ffa" | "teams" | "coop";

export type FaceMode = "webcam" | "synthetic" | "placeholder";

export interface FighterRuntime {
  id: FighterId;
  team: number;
  composite: Composite;
  head: Body;
  hp: number;
  maxHp: number;
  name: string;
  colors: FighterColors;
  controller: FighterController;
  face: FaceMode;
  isLocalHuman: boolean;
  aiSpeedMult?: number;
  aiProfile?: AiProfile | null;
  defensePct?: number;
  grab?: FighterGrabState;
}

export interface RosterBattleConfig {
  mode: BattleMode;
  fighters: Omit<
    FighterRuntime,
    "composite" | "head" | "hp" | "grab"
  >[];
  itemIds?: readonly string[];
}

export function areEnemies(a: FighterRuntime, b: FighterRuntime): boolean {
  if (a.id === b.id) return false;
  if (a.team !== b.team) return true;
  return false;
}

export function livingFighters(fighters: FighterRuntime[]): FighterRuntime[] {
  return fighters.filter((f) => f.hp > 0);
}

export function resolveBattleWinner(
  mode: BattleMode,
  fighters: FighterRuntime[],
): FighterId | null {
  const alive = livingFighters(fighters);
  if (mode === "ffa") {
    if (alive.length === 1) return alive[0]!.id;
    if (alive.length === 0) return null;
    return null;
  }
  if (mode === "teams" || mode === "coop" || mode === "duel") {
    const teams = new Set(alive.map((f) => f.team));
    if (teams.size === 1 && fighters.some((f) => f.hp <= 0)) {
      return alive[0]?.id ?? null;
    }
  }
  return null;
}
