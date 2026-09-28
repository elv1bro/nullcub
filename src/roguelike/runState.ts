import type { DraftCardId, FighterLoadout } from "@/loadout/types";
import { defaultLoadout } from "@/loadout/types";
import { buildDraftPool } from "@/loadout/draft";
import { isPassiveItemId } from "@/loadout/types";
import {
  generateRoguelikeMap,
  getFloorNode,
  getPortal,
  type RoguelikeMap,
  type RoguelikePortal,
} from "./map";

/**
 * Забег рогалика: карта генерируется сразу, хаб (лут + порталы) —
 * до первого боя и после каждого боя. Переход в портал = reload боя.
 */

export type RoguelikeDifficulty = "easy" | "normal" | "hard" | "boss";
export type RoguelikePhase = "hub" | "battle" | "victory" | "defeat";

export interface RoguelikePlayerSlot {
  id: string;
  name: string;
  /** Угол: tl | tr | bl | br */
  corner: "tl" | "tr" | "bl" | "br";
}

export interface RoguelikeRun {
  active: boolean;
  floor: number;
  floorsTotal: number;
  difficulty: RoguelikeDifficulty;
  loadouts: Record<string, FighterLoadout>;
  failed: boolean;
  phase: RoguelikePhase;
  map: RoguelikeMap;
  players: RoguelikePlayerSlot[];
  /** Лут в центре хаба (до боя / после боя). */
  hubLoot: DraftCardId[];
  selectedPortalId: string | null;
  /** Счётчик «перезагрузок» хаба — для remount UI. */
  hubEpoch: number;
}

const FLOORS = 5;
const CORNERS: RoguelikePlayerSlot["corner"][] = ["tl", "tr", "bl", "br"];

let run: RoguelikeRun | null = null;

export function botsForFloor(
  difficulty: RoguelikeDifficulty,
  floor: number,
): number {
  const base =
    difficulty === "easy" ? 2 : difficulty === "normal" ? 3 : 4;
  return Math.min(4, base + Math.floor((floor - 1) / 2));
}

export function ensurePlayerLoadout(
  loadouts: Record<string, FighterLoadout>,
  playerId: string,
): FighterLoadout {
  return loadouts[playerId] ?? defaultLoadout();
}

function buildPlayers(
  names: Record<string, string>,
  playerIds: string[],
): RoguelikePlayerSlot[] {
  const ids = playerIds.slice(0, 4);
  while (ids.length < 4) {
    ids.push(`empty-${ids.length}`);
  }
  return ids.map((id, i) => ({
    id,
    name: names[id] ?? (id.startsWith("empty-") ? "" : `P${i + 1}`),
    corner: CORNERS[i]!,
  }));
}

export interface StartRoguelikeMeta {
  playerIds?: string[];
  playerNames?: Record<string, string>;
  seed?: number;
}

export function startRoguelikeRun(
  initialLoadouts: Record<string, FighterLoadout> = {},
  difficulty: RoguelikeDifficulty = "normal",
  meta: StartRoguelikeMeta = {},
): RoguelikeRun {
  const playerIds = meta.playerIds?.length
    ? meta.playerIds
    : Object.keys(initialLoadouts);
  const ids = playerIds.length ? playerIds : ["you"];
  const loadouts: Record<string, FighterLoadout> = {};
  for (const id of ids) {
    loadouts[id] = initialLoadouts[id] ?? defaultLoadout();
  }

  const map = generateRoguelikeMap({
    floorsTotal: FLOORS,
    difficulty,
    playerCount: ids.length,
    seed: meta.seed,
  });

  const hubLoot = buildDraftPool(ids.length);

  run = {
    active: true,
    floor: 1,
    floorsTotal: map.floorsTotal,
    difficulty,
    loadouts,
    failed: false,
    phase: "hub",
    map,
    players: buildPlayers(meta.playerNames ?? {}, ids),
    hubLoot,
    selectedPortalId: null,
    hubEpoch: 1,
  };
  return run;
}

export function getRoguelikeRun(): RoguelikeRun | null {
  return run;
}

export function getCurrentPortals(): RoguelikePortal[] {
  if (!run) return [];
  return getFloorNode(run.map, run.floor)?.portals ?? [];
}

export function setHubLoot(cards: DraftCardId[]): void {
  if (!run) return;
  run.hubLoot = cards;
}

export function setRunLoadouts(loadouts: Record<string, FighterLoadout>): void {
  if (!run) return;
  run.loadouts = { ...loadouts };
}

function cloneLoadout(lo: FighterLoadout): FighterLoadout {
  return {
    base: lo.base,
    abilities: [...lo.abilities] as FighterLoadout["abilities"],
    items: [...lo.items] as FighterLoadout["items"],
  };
}

/** Положить карту в лодаут; false если нет места (база всегда ок). */
function putCardIntoLoadout(
  lo: FighterLoadout,
  cardId: DraftCardId,
): FighterLoadout | null {
  const next = cloneLoadout(lo);
  if (isPassiveItemId(cardId)) {
    const empty = next.items.findIndex((x) => x == null);
    if (empty < 0) return null;
    next.items[empty] = cardId as FighterLoadout["items"][number];
    return next;
  }
  if (cardId === "dash" || cardId === "flip" || cardId === "brace") {
    next.base = cardId;
    return next;
  }
  const empty = next.abilities.findIndex((x) => x == null);
  if (empty < 0) return null;
  next.abilities[empty] = cardId as FighterLoadout["abilities"][number];
  return next;
}

/** Снять карту с лодаута (не трогает base, если карта = текущая база). */
function stripCardFromLoadout(
  lo: FighterLoadout,
  cardId: DraftCardId,
): FighterLoadout | null {
  const next = cloneLoadout(lo);
  if (isPassiveItemId(cardId)) {
    const idx = next.items.findIndex((x) => x === cardId);
    if (idx < 0) return null;
    next.items[idx] = null;
    return next;
  }
  if (cardId === next.base) {
    // Базу «украсть» нельзя — иначе боец без движения.
    return null;
  }
  const idx = next.abilities.findIndex((x) => x === cardId);
  if (idx < 0) return null;
  next.abilities[idx] = null;
  return next;
}

export function claimHubCard(
  playerId: string,
  cardId: DraftCardId,
): boolean {
  if (!run || run.phase !== "hub") return false;
  const idx = run.hubLoot.indexOf(cardId);
  if (idx < 0) return false;
  if (playerId.startsWith("empty-")) return false;

  const lo = ensurePlayerLoadout(run.loadouts, playerId);
  const next = putCardIntoLoadout(lo, cardId);
  if (!next) return false;

  run.hubLoot = run.hubLoot.slice(0, idx).concat(run.hubLoot.slice(idx + 1));
  run.loadouts = { ...run.loadouts, [playerId]: next };
  return true;
}

/** Отдать лут из центра другому игроку (= claim на его id). */
export function giveHubCard(
  toPlayerId: string,
  cardId: DraftCardId,
): boolean {
  return claimHubCard(toPlayerId, cardId);
}

/**
 * Украсть карту у другого: снять с жертвы → положить вору.
 * Если у вора нет места — карта падает обратно в центр (хаб).
 */
export function stealCard(
  thiefId: string,
  victimId: string,
  cardId: DraftCardId,
): boolean {
  if (!run || run.phase !== "hub") return false;
  if (thiefId === victimId) return false;
  if (thiefId.startsWith("empty-") || victimId.startsWith("empty-")) return false;

  const victimLo = ensurePlayerLoadout(run.loadouts, victimId);
  const stripped = stripCardFromLoadout(victimLo, cardId);
  if (!stripped) return false;

  const thiefLo = ensurePlayerLoadout(run.loadouts, thiefId);
  const gained = putCardIntoLoadout(thiefLo, cardId);

  run.loadouts = {
    ...run.loadouts,
    [victimId]: stripped,
    ...(gained
      ? { [thiefId]: gained }
      : {}),
  };
  if (!gained) {
    run.hubLoot = [...run.hubLoot, cardId];
  }
  return true;
}

/** Выкинуть карту из своего лодаута обратно в центр. */
export function dropCardToHub(playerId: string, cardId: DraftCardId): boolean {
  if (!run || run.phase !== "hub") return false;
  if (playerId.startsWith("empty-")) return false;
  const lo = ensurePlayerLoadout(run.loadouts, playerId);
  const stripped = stripCardFromLoadout(lo, cardId);
  if (!stripped) return false;
  run.loadouts = { ...run.loadouts, [playerId]: stripped };
  run.hubLoot = [...run.hubLoot, cardId];
  return true;
}

export function setPlayerBase(
  playerId: string,
  base: FighterLoadout["base"],
): void {
  if (!run) return;
  const lo = ensurePlayerLoadout(run.loadouts, playerId);
  run.loadouts = { ...run.loadouts, [playerId]: { ...lo, base } };
}

/** Войти в портал → бой (перезагрузка арены). */
export function enterPortal(portalId: string): RoguelikePortal | null {
  if (!run || !run.active || run.phase !== "hub") return null;
  const found = getPortal(run.map, portalId);
  if (!found || found.floor.floor !== run.floor) return null;
  if (found.portal.cleared) return null;
  run.selectedPortalId = portalId;
  run.phase = "battle";
  return found.portal;
}

/**
 * Исход боя. Победа → хаб следующего этажа с лутом портала.
 * Поражение → конец забега.
 */
export function resolveBattle(won: boolean): RoguelikeRun | null {
  if (!run) return null;
  if (!won) {
    run.failed = true;
    run.active = false;
    run.phase = "defeat";
    run.hubEpoch += 1;
    return run;
  }

  const portalId = run.selectedPortalId;
  if (portalId) {
    const found = getPortal(run.map, portalId);
    if (found) {
      found.portal.cleared = true;
      run.hubLoot = [...found.portal.rewardPool];
    }
  }

  if (run.floor >= run.floorsTotal) {
    run.active = false;
    run.phase = "victory";
    run.hubEpoch += 1;
    return run;
  }

  run.floor += 1;
  run.phase = "hub";
  run.selectedPortalId = null;
  run.hubEpoch += 1;

  // Если лут портала пуст — свежий пул на этаж.
  if (run.hubLoot.length === 0) {
    const humans = run.players.filter((p) => !p.id.startsWith("empty-")).length;
    run.hubLoot = buildDraftPool(Math.max(1, humans));
  }
  return run;
}

export function advanceRoguelikeFloor(): RoguelikeRun | null {
  if (!run || !run.active) return null;
  if (run.floor >= run.floorsTotal) {
    run.active = false;
    run.phase = "victory";
    return run;
  }
  run.floor += 1;
  run.phase = "hub";
  run.hubEpoch += 1;
  return run;
}

export function failRoguelikeRun(): void {
  if (!run) return;
  run.failed = true;
  run.active = false;
  run.phase = "defeat";
  run.hubEpoch += 1;
}

export function clearRoguelikeRun(): void {
  run = null;
}

export function selectedPortal(): RoguelikePortal | null {
  if (!run?.selectedPortalId) return null;
  return getPortal(run.map, run.selectedPortalId)?.portal ?? null;
}
