/** Модель монстра из мастерской (относительные координаты). */

import { type MonsterLinkType } from "./linkTypes";

export type MonsterPartSize = "s" | "m" | "l" | "head";

/** hurtbox — получает урон; armor — только физика, без HP-урона */
export type MonsterPartRole = "hurtbox" | "armor";

export interface MonsterPartDef {
  x: number;
  y: number;
  radius: number;
  isHead: boolean;
  role?: MonsterPartRole;
  /** Шип: контактный урон (природное оружие, pierce). */
  spike?: boolean;
}

export interface MonsterLinkDef {
  a: number;
  b: number;
  type?: MonsterLinkType;
}

export interface MonsterStats {
  maxHp: number;
  /** 0–80: процент снижения входящего урона */
  defense: number;
}

export interface MonsterDef {
  id: string;
  name: string;
  parts: MonsterPartDef[];
  links: MonsterLinkDef[];
  stats?: MonsterStats;
  createdAt: number;
}

export const PART_RADIUS: Record<MonsterPartSize, number> = {
  s: 8,
  m: 12,
  l: 16,
  head: 20,
};

export function monsterMaxHp(partCount: number): number {
  return Math.max(40, partCount * 40);
}

export function resolveMonsterMaxHp(def: MonsterDef): number {
  const fromStats = def.stats?.maxHp;
  if (typeof fromStats === "number" && fromStats > 0) return fromStats;
  return monsterMaxHp(def.parts.length);
}

export function resolveMonsterDefense(def: MonsterDef): number {
  return Math.max(0, Math.min(80, def.stats?.defense ?? 0));
}

export function resolvePartRole(part: MonsterPartDef): MonsterPartRole {
  if (part.isHead) return "hurtbox";
  return part.role === "armor" ? "armor" : "hurtbox";
}

export function normalizeMonsterDef(def: MonsterDef): MonsterDef {
  return {
    ...def,
    parts: def.parts.map((p) => ({
      ...p,
      role: resolvePartRole(p),
    })),
    stats: {
      maxHp: resolveMonsterMaxHp(def),
      defense: resolveMonsterDefense(def),
    },
    links: def.links.map((l) => ({ ...l, type: l.type ?? "rigid" })),
  };
}

export function createEmptyMonster(name = "Монстр"): MonsterDef {
  return normalizeMonsterDef({
    id: crypto.randomUUID(),
    name,
    parts: [],
    links: [],
    createdAt: Date.now(),
  });
}
