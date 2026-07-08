import type { MonsterPartRole } from "@/monster/monsterTypes";
import type { BlockKind } from "./blueprintTypes";

export interface BlockMeta {
  blockKind: BlockKind;
  isHead: boolean;
  role: MonsterPartRole;
  spikeDamage: number;
  massScale: number;
}

export function createBlockMeta(blockKind: BlockKind): BlockMeta {
  return {
    blockKind,
    isHead: blockKind === "head",
    role: blockKind === "armor" ? "armor" : "hurtbox",
    spikeDamage: blockKind === "spike" ? 1 : 0,
    massScale: blockKind === "mass" ? 2.4 : blockKind === "joint" ? 0.6 : 1,
  };
}

export function partBodyLabelFromMeta(meta: BlockMeta): string {
  if (meta.isHead) return "Head";
  if (meta.role === "armor") return "Armor";
  if (meta.blockKind === "grip") return "Grip";
  if (meta.blockKind === "spike") return "Spike";
  if (meta.blockKind === "joint") return "Joint";
  if (meta.blockKind === "mass") return "Mass";
  return "Chest";
}

/** Совместимость со старым PartMeta. */
export function toLegacyPartMeta(meta: BlockMeta): {
  isHead: boolean;
  role: MonsterPartRole;
} {
  return { isHead: meta.isHead, role: meta.role };
}
