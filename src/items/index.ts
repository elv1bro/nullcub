import "./damageTypes";
import { items } from "./registry";
import {
  DEFAULT_ARENA_WEAPON_IDS,
  WEAPON_CATALOG,
  WEAPON_CATALOG_IDS,
} from "./defs";
import { buildItem } from "./buildItem";
import { blueprintToItemDef } from "@/workshop/blueprintAdapters";
import { listBlueprints } from "@/workshop/blueprintStore";
import type { Composite } from "matter-js";

export * from "./registry";
export * from "./damageTypes";
export * from "./buildItem";
export * from "./disarm";
export * from "./resolveWeaponHit";
export * from "./weaponHold";
export * from "./weaponL10n";
export {
  WEAPON_CATALOG,
  WEAPON_CATALOG_IDS,
  DEFAULT_ARENA_WEAPON_IDS,
  LEGACY_WEAPON_IDS,
} from "./defs";

for (const def of WEAPON_CATALOG) {
  items.register(def);
}

/** Пользовательские оружия из Blueprint Studio (lazy — без localStorage при импорте в core). */
export function registerCustomItems(): void {
  if (typeof localStorage === "undefined") return;
  for (const bp of listBlueprints("item")) {
    items.register(blueprintToItemDef(bp));
  }
}

/** В браузере с workshop — вызывается из main.tsx. */
export function registerDefaultItems(): void {
  registerCustomItems();
}

/** @deprecated имя — теперь DEFAULT_ARENA_WEAPON_IDS */
export const DEFAULT_ARENA_ITEMS = DEFAULT_ARENA_WEAPON_IDS;

/** Углы арены — подальше от спавна бойцов (~333 и ~666 по X). */
export const ARENA_ITEM_SPAWN_POSITIONS = [
  { x: 140, y: 200 },
  { x: 860, y: 200 },
  { x: 140, y: 800 },
  { x: 860, y: 800 },
] as const;

export function spawnArenaItems(
  itemIds: readonly string[] = DEFAULT_ARENA_WEAPON_IDS,
  positions: { x: number; y: number }[] = [...ARENA_ITEM_SPAWN_POSITIONS],
): Composite[] {
  return itemIds.map((id, i) => {
    const pos = positions[i % positions.length]!;
    return buildItem(items.get(id), pos.x, pos.y);
  });
}

/** Случайная выборка из каталога (без повторов), для арены. */
export function pickArenaWeapons(
  count: number,
  rng: () => number = Math.random,
): string[] {
  const pool = [...WEAPON_CATALOG_IDS];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = pool[i]!;
    pool[i] = pool[j]!;
    pool[j] = tmp;
  }
  return pool.slice(0, Math.max(0, Math.min(count, pool.length)));
}
