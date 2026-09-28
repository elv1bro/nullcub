import { WEAPON_CATALOG } from "./catalog";
import type { ItemDef } from "../registry";

function byId(id: string): ItemDef {
  const def = WEAPON_CATALOG.find((d) => d.id === id);
  if (!def) throw new Error(`legacy weapon missing: ${id}`);
  return def;
}

export const fryingPanDef = byId("frying-pan");
export const spearDef = byId("spear");
export const chainFlailDef = byId("chain-flail");
export const torchDef = byId("torch");
