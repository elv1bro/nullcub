import { draftableAbilityIds } from "./abilities";
import { allItemIds } from "./items";
import type { DraftCardId } from "./types";

export type DraftInventory = Record<string, DraftCardId[]>;

export interface DraftMutationResult {
  ok: boolean;
  pool: DraftCardId[];
  inventoryByPlayer: DraftInventory;
}

/** Все уникальные карты, доступные в драфте. */
export function allDraftableCards(): DraftCardId[] {
  return [...draftableAbilityIds(), ...allItemIds()];
}

function shuffleInPlace<T>(arr: T[], rng: () => number): T[] {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = arr[i]!;
    arr[i] = arr[j]!;
    arr[j] = tmp;
  }
  return arr;
}

/**
 * Пул драфта: N+1 случайных уникальных карт из способностей (не база) + предметов.
 */
export function buildDraftPool(
  playerCount: number,
  rng: () => number = Math.random,
): DraftCardId[] {
  const n = Math.max(0, Math.floor(playerCount));
  const size = n + 1;
  const cards = shuffleInPlace(allDraftableCards(), rng);
  return cards.slice(0, Math.min(size, cards.length));
}

/** Забрать карту из пула в инвентарь игрока. */
export function claimCard(
  pool: DraftCardId[],
  inventoryByPlayer: DraftInventory,
  playerId: string,
  cardId: DraftCardId,
): DraftMutationResult {
  const idx = pool.indexOf(cardId);
  if (idx < 0) {
    return { ok: false, pool, inventoryByPlayer };
  }
  const nextPool = pool.slice(0, idx).concat(pool.slice(idx + 1));
  const prev = inventoryByPlayer[playerId] ?? [];
  return {
    ok: true,
    pool: nextPool,
    inventoryByPlayer: {
      ...inventoryByPlayer,
      [playerId]: [...prev, cardId],
    },
  };
}

/** Вернуть карту из инвентаря игрока в пул. */
export function releaseCard(
  pool: DraftCardId[],
  inventoryByPlayer: DraftInventory,
  playerId: string,
  cardId: DraftCardId,
): DraftMutationResult {
  const prev = inventoryByPlayer[playerId] ?? [];
  const idx = prev.indexOf(cardId);
  if (idx < 0) {
    return { ok: false, pool, inventoryByPlayer };
  }
  const nextInv = prev.slice(0, idx).concat(prev.slice(idx + 1));
  return {
    ok: true,
    pool: [...pool, cardId],
    inventoryByPlayer: {
      ...inventoryByPlayer,
      [playerId]: nextInv,
    },
  };
}
