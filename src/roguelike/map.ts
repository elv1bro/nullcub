import { allDraftableCards } from "@/loadout/draft";
import type { DraftCardId } from "@/loadout/types";
import type { RoguelikeDifficulty } from "./runState";

/**
 * Порталы — выходы из комнаты хаба в три стороны.
 * Визуально разнесены по экрану (лево / вперёд / право),
 * логически — одна «выходная» стена куба.
 */
export type PortalDirection = "left" | "forward" | "right";

export type CubeFace = "east";

export interface RoguelikePortal {
  id: string;
  face: CubeFace;
  direction: PortalDirection;
  /** 0..2 вдоль грани. */
  slot: number;
  botCount: number;
  difficulty: RoguelikeDifficulty;
  /** Что видно в окне портала. */
  lootPreview: DraftCardId[];
  /** Лут в центр хаба после победы. */
  rewardPool: DraftCardId[];
  cleared: boolean;
}

export interface RoguelikeFloorNode {
  floor: number;
  portals: RoguelikePortal[];
}

export interface RoguelikeMap {
  seed: number;
  floorsTotal: number;
  floors: RoguelikeFloorNode[];
}

const DIRECTIONS: PortalDirection[] = ["left", "forward", "right"];

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle<T>(arr: T[], rng: () => number): T[] {
  const out = arr.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = out[i]!;
    out[i] = out[j]!;
    out[j] = tmp;
  }
  return out;
}

function pickUnique(
  deck: DraftCardId[],
  count: number,
  rng: () => number,
): DraftCardId[] {
  return shuffle(deck, rng).slice(0, Math.min(count, deck.length));
}

function difficultyForFloor(
  base: RoguelikeDifficulty,
  floor: number,
  floorsTotal: number,
): RoguelikeDifficulty {
  if (floor >= floorsTotal) return "boss";
  if (base === "boss") return floor >= floorsTotal - 1 ? "boss" : "hard";
  if (floor >= floorsTotal - 1) return "hard";
  if (floor >= Math.ceil(floorsTotal * 0.6)) {
    return base === "easy" ? "normal" : base === "normal" ? "hard" : "hard";
  }
  return base;
}

function botCountFor(
  difficulty: RoguelikeDifficulty,
  floor: number,
): number {
  const base =
    difficulty === "easy" ? 2 : difficulty === "normal" ? 3 : 4;
  return Math.min(4, base + Math.floor((floor - 1) / 2));
}

export interface GenerateMapOpts {
  floorsTotal?: number;
  difficulty?: RoguelikeDifficulty;
  seed?: number;
  playerCount?: number;
}

/** Всегда 3 портала на этаж — влево / вперёд / вправо. */
export function generateRoguelikeMap(opts: GenerateMapOpts = {}): RoguelikeMap {
  const floorsTotal = opts.floorsTotal ?? 5;
  const difficulty = opts.difficulty ?? "normal";
  const seed = opts.seed ?? (Math.floor(Math.random() * 1e9) || 1);
  const playerCount = Math.max(1, opts.playerCount ?? 1);
  const rng = mulberry32(seed);
  const deck = allDraftableCards();

  const floors: RoguelikeFloorNode[] = [];
  for (let floor = 1; floor <= floorsTotal; floor++) {
    const floorDiff = difficultyForFloor(difficulty, floor, floorsTotal);
    const portals: RoguelikePortal[] = [];
    for (let slot = 0; slot < DIRECTIONS.length; slot++) {
      const direction = DIRECTIONS[slot]!;
      const rewardCount = Math.min(4, playerCount + 1 + (slot === 1 ? 0 : 1));
      const rewardPool = pickUnique(deck, rewardCount, rng);
      const previewCount = Math.min(3, Math.max(1, rewardPool.length));
      const lootPreview = rewardPool.slice(0, previewCount);
      const botCount = Math.min(
        4,
        Math.max(1, botCountFor(floorDiff, floor) + (slot === 2 ? 1 : 0)),
      );
      portals.push({
        id: `f${floor}-${direction}`,
        face: "east",
        direction,
        slot,
        botCount,
        difficulty:
          direction === "forward" && floor === floorsTotal
            ? "boss"
            : floorDiff,
        lootPreview,
        rewardPool,
        cleared: false,
      });
    }
    floors.push({ floor, portals });
  }

  return { seed, floorsTotal, floors };
}

export function getFloorNode(
  map: RoguelikeMap,
  floor: number,
): RoguelikeFloorNode | null {
  return map.floors.find((f) => f.floor === floor) ?? null;
}

export function getPortal(
  map: RoguelikeMap,
  portalId: string,
): { floor: RoguelikeFloorNode; portal: RoguelikePortal } | null {
  for (const floor of map.floors) {
    const portal = floor.portals.find((p) => p.id === portalId);
    if (portal) return { floor, portal };
  }
  return null;
}
