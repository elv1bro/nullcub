import type { MonsterLinkType } from "@/monster/linkTypes";

export type ItemLinkSpec = {
  from: number;
  to: number;
  type: MonsterLinkType;
};

export type ItemBodySpec = {
  x: number;
  y: number;
  radius: number;
  label?: string;
  grip?: boolean;
  render?: { fillStyle?: string };
};

export interface ItemDef {
  id: string;
  name: string;
  damageType: string;
  atkMult: number;
  dropChanceMult: number;
  toughnessBonus: number;
  bodies: ItemBodySpec[];
  links: ItemLinkSpec[];
}

class ItemRegistry {
  private map = new Map<string, ItemDef>();

  register(def: ItemDef): void {
    if (this.map.has(def.id)) return;
    this.map.set(def.id, def);
  }

  get(id: string): ItemDef {
    const def = this.map.get(id);
    if (!def) throw new Error(`Unknown item: ${id}`);
    return def;
  }

  all(): ItemDef[] {
    return [...this.map.values()];
  }
}

export const items = new ItemRegistry();
