import type { Body } from "matter-js";
import type { MonsterPartRole } from "./monsterTypes";

export type PartMeta = { isHead: boolean; role: MonsterPartRole; spike?: boolean };

export function partBodyLabel(meta: PartMeta): string {
  if (meta.spike) return "Spike";
  if (meta.role === "armor") return "Armor";
  return meta.isHead ? "Head" : "Chest";
}

export function partRenderStyle(meta: PartMeta): {
  fillStyle: string;
  strokeStyle: string;
  lineWidth: number;
} {
  if (meta.spike) {
    return { fillStyle: "#dc2626", strokeStyle: "#fca5a5", lineWidth: 2 };
  }
  if (meta.role === "armor") {
    return { fillStyle: "#475569", strokeStyle: "#94a3b8", lineWidth: 2 };
  }
  if (meta.isHead) {
    return { fillStyle: "#a855f7", strokeStyle: "#c084fc", lineWidth: 1 };
  }
  return { fillStyle: "#7e22ce", strokeStyle: "#a855f7", lineWidth: 1 };
}

export function applyPartRender(body: Body, meta: PartMeta): void {
  const style = partRenderStyle(meta);
  body.label = partBodyLabel(meta);
  body.render.fillStyle = style.fillStyle;
  body.render.strokeStyle = style.strokeStyle;
  body.render.lineWidth = style.lineWidth;
}
