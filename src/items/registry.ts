import type { MonsterLinkType } from "@/monster/linkTypes";

export type ItemLinkSpec = {
  from: number;
  to: number;
  type: MonsterLinkType;
};

/** Часть (только для верёвочного/составного оружия). */
export type ItemBodySpec = {
  x: number;
  y: number;
  radius?: number;
  width?: number;
  height?: number;
  label?: string;
  grip?: boolean;
  render?: { fillStyle?: string; strokeStyle?: string; lineWidth?: number };
};

/** Часть цельного оружия (локальные координаты design-origin). */
export type SolidWeaponPart = {
  x: number;
  y: number;
  /** Прямоугольник. */
  w?: number;
  h?: number;
  /** Круг (если нет w/h). */
  r?: number;
  angle?: number;
  color: string;
  stroke?: string;
  label?: string;
};

/** Цельное жёсткое оружие — один collider с массой (опционально compound parts). */
export type SolidWeaponSpec = {
  /** Длина вдоль локальной оси X (для fallback rect / инерции). */
  length: number;
  thickness: number;
  /**
   * Grip в координатах design-origin (тот же, что у parts).
   * После Body.create пересчитывается относительно COM.
   */
  gripLocal: { x: number; y: number };
  /** Масса Matter (кг-условные). Тяжелее → сильнее мешает бегу. */
  mass: number;
  color: string;
  stroke?: string;
  shape?: "rect" | "circle";
  /** Для circle: радиус (иначе thickness/2). */
  radius?: number;
  /**
   * Части одного rigid-тела (Matter.Body.create({ parts })).
   * Если нет — fallback на один rect/circle.
   */
  parts?: SolidWeaponPart[];
};

export interface ItemDef {
  id: string;
  name: string;
  damageType: string;
  atkMult: number;
  dropChanceMult: number;
  toughnessBonus: number;
  /** Верёвочное / бусины; для solid — пусто или декоративная раскладка. */
  bodies: ItemBodySpec[];
  links: ItemLinkSpec[];
  /** Если задано — buildItem делает одно цельное тело. */
  solid?: SolidWeaponSpec;
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
