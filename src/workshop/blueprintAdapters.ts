import type { Composite } from "matter-js";
import type { MonsterDef } from "@/monster/monsterTypes";
import { normalizeMonsterDef } from "@/monster/monsterTypes";
import type { ItemDef } from "@/items/registry";
import type { BlockMeta } from "./blockMeta";
import { createBlockMeta } from "./blockMeta";
import type { BlueprintDef, BlueprintMeta, WorkshopKind } from "./blueprintTypes";
import { DEFAULT_BLUEPRINT_META } from "./blueprintTypes";

export function monsterDefToBlueprint(def: MonsterDef): BlueprintDef {
  return {
    id: def.id,
    name: def.name,
    kind: "monster",
    parts: def.parts.map((p) => ({
      x: p.x,
      y: p.y,
      radius: p.radius,
      blockKind: p.isHead
        ? "head"
        : p.spike
          ? "spike"
          : p.role === "armor"
            ? "armor"
            : "core",
    })),
    links: def.links.map((l) => ({ a: l.a, b: l.b, type: l.type })),
    meta: {
      maxHp: def.stats?.maxHp,
      defense: def.stats?.defense,
    },
    createdAt: def.createdAt,
  };
}

export function blueprintToMonsterDef(def: BlueprintDef): MonsterDef {
  return normalizeMonsterDef({
    id: def.id,
    name: def.name,
    parts: def.parts.map((p) => ({
      x: p.x,
      y: p.y,
      radius: p.radius,
      isHead: p.blockKind === "head",
      role: p.blockKind === "armor" ? "armor" : "hurtbox",
      spike: p.blockKind === "spike",
    })),
    links: def.links.map((l) => ({ a: l.a, b: l.b, type: l.type })),
    stats: {
      maxHp: def.meta?.maxHp ?? 200,
      defense: def.meta?.defense ?? 0,
    },
    createdAt: def.createdAt,
  });
}

export function blueprintToItemDef(def: BlueprintDef): ItemDef {
  const meta = { ...DEFAULT_BLUEPRINT_META.item, ...def.meta };
  return {
    id: def.id,
    name: def.name,
    damageType: meta.damageType ?? "blunt",
    atkMult: meta.atkMult ?? 1,
    dropChanceMult: meta.dropChanceMult ?? 1,
    toughnessBonus: meta.toughnessBonus ?? 0,
    bodies: def.parts.map((p) => ({
      x: p.x,
      y: p.y,
      radius: p.radius,
      grip: p.blockKind === "grip",
      label: p.blockKind,
      render: { fillStyle: blockFill(p.blockKind) },
    })),
    links: def.links.map((l) => ({
      from: l.a,
      to: l.b,
      type: l.type ?? "rigid",
    })),
  };
}

export function blockMetaFromBlueprintPart(
  part: BlueprintDef["parts"][number],
): BlockMeta {
  return createBlockMeta(part.blockKind);
}

function blockFill(kind: BlueprintDef["parts"][number]["blockKind"]): string {
  switch (kind) {
    case "grip":
      return "#fbbf24";
    case "spike":
      return "#f87171";
    case "mass":
      return "#64748b";
    case "joint":
      return "#c4b5fd";
    case "armor":
      return "#475569";
    default:
      return "#94a3b8";
  }
}

export function validateBlueprint(
  def: BlueprintDef,
): { ok: true } | { ok: false; reason: string } {
  if (def.parts.length === 0) return { ok: false, reason: "needParts" };

  if (def.kind === "monster") {
    if (!def.parts.some((p) => p.blockKind === "head")) {
      return { ok: false, reason: "needHead" };
    }
    if (
      !def.parts.some((p) => p.blockKind === "core" || p.blockKind === "head")
    ) {
      return { ok: false, reason: "needHurtbox" };
    }
  }

  if (def.kind === "item") {
    if (!def.parts.some((p) => p.blockKind === "grip")) {
      return { ok: false, reason: "needGrip" };
    }
  }

  return { ok: true };
}

export function defaultBlueprintName(kind: WorkshopKind): string {
  const tag =
    kind === "monster" ? "MONSTER" : kind === "item" ? "ITEM" : "ARENA";
  const suffix = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `${tag} ${suffix}`;
}

export function emptyBlueprint(kind: WorkshopKind): BlueprintDef {
  return {
    id: crypto.randomUUID(),
    name: defaultBlueprintName(kind),
    kind,
    parts: [],
    links: [],
    meta: { ...DEFAULT_BLUEPRINT_META[kind] },
    createdAt: Date.now(),
  };
}

export function snapshotBlueprintFromComposite(
  composite: Composite,
  meta: BlockMeta[],
  links: BlueprintDef["links"],
  kind: WorkshopKind,
  name: string,
  id: string,
  blueprintMeta?: BlueprintMeta,
): BlueprintDef {
  const positions = composite.bodies.map((b) => ({
    x: b.position.x,
    y: b.position.y,
  }));
  const center = positions.reduce(
    (acc, p) => ({ x: acc.x + p.x, y: acc.y + p.y }),
    { x: 0, y: 0 },
  );
  const c = {
    x: center.x / positions.length,
    y: center.y / positions.length,
  };

  return {
    id,
    name,
    kind,
    parts: composite.bodies.map((body, index) => ({
      x: body.position.x - c.x,
      y: body.position.y - c.y,
      radius: body.circleRadius ?? 10,
      blockKind: meta[index]?.blockKind ?? "core",
    })),
    links: links.map((l) => ({ ...l })),
    meta: blueprintMeta,
    createdAt: Date.now(),
  };
}
