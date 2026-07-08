import { buildItem } from "@/items/buildItem";
import { buildMonster } from "@/monster/buildMonster";
import type { BlueprintDef } from "./blueprintTypes";
import { blueprintToItemDef, blueprintToMonsterDef } from "./blueprintAdapters";

export function buildBlueprintPhysics(
  def: BlueprintDef,
  worldX: number,
  worldY: number,
) {
  if (def.kind === "monster") {
    return buildMonster(blueprintToMonsterDef(def), worldX, worldY);
  }
  if (def.kind === "item" || def.kind === "arena") {
    const composite = buildItem(blueprintToItemDef(def), worldX, worldY);
    return {
      composite,
      head: undefined,
      maxHp: 0,
      colors: { main: "#94a3b8", secondary: "#64748b" },
    };
  }
  return null;
}
