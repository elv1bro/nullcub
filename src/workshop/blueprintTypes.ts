import type { MonsterLinkType } from "@/monster/linkTypes";

/** Режим мастерской — что собираем. */
export type WorkshopKind = "monster" | "item" | "arena";

/** Семантика блока — задаёт физику и бой. */
export type BlockKind =
  | "head"
  | "core"
  | "armor"
  | "spike"
  | "grip"
  | "joint"
  | "mass";

export interface BlueprintPartDef {
  x: number;
  y: number;
  radius: number;
  blockKind: BlockKind;
}

export interface BlueprintLinkDef {
  a: number;
  b: number;
  type?: MonsterLinkType;
}

export interface BlueprintMeta {
  maxHp?: number;
  defense?: number;
  damageType?: string;
  atkMult?: number;
  dropChanceMult?: number;
  toughnessBonus?: number;
  /** arena: закрепленные части арены */
  static?: boolean;
}

export interface BlueprintDef {
  id: string;
  name: string;
  kind: WorkshopKind;
  parts: BlueprintPartDef[];
  links: BlueprintLinkDef[];
  meta?: BlueprintMeta;
  createdAt: number;
}

export const DEFAULT_BLUEPRINT_META: Record<WorkshopKind, BlueprintMeta> = {
  monster: { maxHp: 200, defense: 0 },
  item: { damageType: "blunt", atkMult: 1.1, dropChanceMult: 1, toughnessBonus: 0 },
  arena: { static: false },
};
