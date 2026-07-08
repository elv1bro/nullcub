import type { Body } from "matter-js";
import Matter from "matter-js";
import { type MonsterLinkType } from "@/monster/linkTypes";
import type { BlockMeta } from "./blockMeta";
import { partBodyLabelFromMeta } from "./blockMeta";
import type { PartMeta } from "@/monster/partStyle";

const LINK_BLUEPRINT: Record<MonsterLinkType, string> = {
  rigid: "rgba(252, 165, 165, 0.9)",
  spring: "rgba(134, 239, 172, 0.9)",
  rope: "rgba(253, 224, 71, 0.9)",
};

const BLOCK_STYLE: Record<
  BlockMeta["blockKind"],
  { fill: string; stroke: string; lineWidth: number }
> = {
  head: {
    fill: "rgba(255, 255, 255, 0.24)",
    stroke: "#f8fafc",
    lineWidth: 2.5,
  },
  core: {
    fill: "rgba(186, 230, 253, 0.22)",
    stroke: "#e0f2fe",
    lineWidth: 2,
  },
  armor: {
    fill: "rgba(15, 23, 42, 0.42)",
    stroke: "#e2e8f0",
    lineWidth: 2,
  },
  spike: {
    fill: "rgba(248, 113, 113, 0.28)",
    stroke: "#fecaca",
    lineWidth: 2,
  },
  grip: {
    fill: "rgba(251, 191, 36, 0.28)",
    stroke: "#fde68a",
    lineWidth: 2,
  },
  joint: {
    fill: "rgba(196, 181, 253, 0.24)",
    stroke: "#ddd6fe",
    lineWidth: 1.5,
  },
  mass: {
    fill: "rgba(100, 116, 139, 0.35)",
    stroke: "#cbd5e1",
    lineWidth: 2,
  },
};

/** Чертёжный стиль частей на синей бумаге. */
export function applyBlueprintPartRender(body: Body, meta: BlockMeta | PartMeta): void {
  const blockKind =
    "blockKind" in meta
      ? meta.blockKind
      : meta.isHead
        ? "head"
        : meta.role === "armor"
          ? "armor"
          : "core";
  const style = BLOCK_STYLE[blockKind];
  body.label =
    "blockKind" in meta ? partBodyLabelFromMeta(meta) : meta.isHead ? "Head" : meta.role === "armor" ? "Armor" : "Chest";
  body.render.fillStyle = style.fill;
  body.render.strokeStyle = style.stroke;
  body.render.lineWidth = style.lineWidth;

  if ("massScale" in meta && meta.massScale !== 1) {
    Matter.Body.setMass(body, body.mass * meta.massScale);
  }
}

export function blueprintLinkStroke(type: MonsterLinkType): string {
  return LINK_BLUEPRINT[type];
}

export function freezeWorkshopBody(body: Body): void {
  Matter.Body.setStatic(body, true);
  Matter.Body.setVelocity(body, { x: 0, y: 0 });
  Matter.Body.setAngularVelocity(body, 0);
  body.frictionAir = 1;
  body.restitution = 0;
}

export function unfreezeWorkshopBody(body: Body): void {
  Matter.Body.setStatic(body, false);
  body.frictionAir = 0.02;
  body.restitution = 0;
}

export function syncWorkshopComposite(
  composite: Matter.Composite,
  meta: BlockMeta[],
): void {
  composite.bodies.forEach((body, index) => {
    const m = meta[index];
    if (m) applyBlueprintPartRender(body, m);
    freezeWorkshopBody(body);
  });
}
