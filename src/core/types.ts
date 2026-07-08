import type { AiProfile } from "@/battle/aiProfiles";
import type { BotBrainState } from "@/battle/aiLogic";
import type { NetInputPayload } from "@/net/protocol";
import type { Composite, Body, Engine } from "matter-js";

export type FighterRole = "player" | "opponent" | string;

export interface CoreFighterSpec {
  id: FighterRole;
  composite: Composite;
  head: Body;
  maxHp: number;
  /** Бот — AI управляет вместо input. */
  aiProfile?: AiProfile | null;
  /**
   * Этот боец получает усиленный урон от бота (×BOT_DAMAGE_MULTIPLIER).
   * Ставится на ИГРОКА в боях против AI (легаси-семантика «бот бьёт сильнее»).
   */
  isBotDamageTarget?: boolean;
  defensePct?: number;
}

export interface CoreFighterRuntime extends CoreFighterSpec {
  hp: number;
  brain?: BotBrainState;
  input: NetInputPayload;
  moveSpeedMult: number;
  inputBlocked: boolean;
  braceActive: boolean;
}

export interface BattleSessionConfig {
  arenaSize: number;
  fighters: CoreFighterSpec[];
  itemComposites?: Composite[];
  battleStartMs?: number;
  /** id composite → fighter id */
  playerCompositeId?: number;
  opponentCompositeId?: number;
  /** Если передан — не создаём свой Engine (интеграция с matter4react). */
  engine?: Engine;
  /** Существующие стены арены (matter4react SurroundingWalls). */
  walls?: Composite;
  /** Не добавлять composite в world (уже добавлены React). */
  compositesInWorld?: boolean;
  /** Блок урона до beginBattle() — для серверного settle после спавна. */
  damageLocked?: boolean;
  /** Длительность spawn grace после beginBattle() (мс). */
  spawnGraceMs?: number;
}

export interface BattleSnapshot {
  tick: number;
  t: number;
  bodies: Float32Array;
  fighterHp: Record<FighterRole, number>;
  battleOver: boolean;
  winner: FighterRole | null;
}

export interface CoreEngineBundle {
  engine: Engine;
  walls: Composite;
  fighters: CoreFighterRuntime[];
  itemComposites: Composite[];
  allComposites: Composite[];
}
