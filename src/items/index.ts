import "./damageTypes";
import { items } from "./registry";
import {
  chainFlailDef,
  fryingPanDef,
  spearDef,
  torchDef,
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

items.register(fryingPanDef);
items.register(spearDef);
items.register(chainFlailDef);
items.register(torchDef);

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

export const DEFAULT_ARENA_ITEMS = [
  "frying-pan",
  "spear",
  "chain-flail",
  "torch",
] as const;

/** Углы арены — подальше от спавна бойцов (~333 и ~666 по X). */
export const ARENA_ITEM_SPAWN_POSITIONS = [
  { x: 140, y: 200 },
  { x: 860, y: 200 },
  { x: 140, y: 800 },
  { x: 860, y: 800 },
] as const;

export function spawnArenaItems(
  itemIds: readonly string[],
  positions: { x: number; y: number }[],
): Composite[] {
  return itemIds.map((id, i) => {
    const pos = positions[i % positions.length]!;
    return buildItem(items.get(id), pos.x, pos.y);
  });
}
