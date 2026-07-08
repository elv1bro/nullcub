import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import Matter, { Body, Composite, Vector } from "matter-js";
import {
  createLinkConstraints,
  defaultLinkType,
  updateMonsterRopeConstraints,
} from "./linkTypes";
import { applyPartRender, partBodyLabel } from "./partStyle";
import type { MonsterDef, MonsterPartDef } from "./monsterTypes";
import { resolveMonsterMaxHp, resolvePartRole } from "./monsterTypes";

export interface BuiltMonster {
  composite: Composite;
  head: Body | undefined;
  maxHp: number;
  colors: { main: string; secondary: string };
}

function centroid(parts: MonsterPartDef[]): Vector {
  if (parts.length === 0) return Vector.create(0, 0);
  const sum = parts.reduce(
    (acc, p) => Vector.add(acc, Vector.create(p.x, p.y)),
    Vector.create(0, 0),
  );
  return Vector.div(sum, parts.length);
}

/** Собирает ragdoll-монстра в мировых координатах. */
export function buildMonster(
  def: MonsterDef,
  worldX: number,
  worldY: number,
  colors: { main: string; secondary: string } = {
    main: "#a855f7",
    secondary: "#7e22ce",
  },
): BuiltMonster | null {
  if (def.parts.length === 0) return null;

  const center = centroid(def.parts);
  const group = Body.nextGroup(true);
  const bodies: Body[] = [];

  for (const part of def.parts) {
    const pos = Vector.create(
      worldX + (part.x - center.x),
      worldY + (part.y - center.y),
    );
    const meta = {
      isHead: part.isHead,
      role: resolvePartRole(part),
      spike: part.spike ?? false,
    };
    const style = {
      fillStyle: part.isHead ? colors.main : colors.secondary,
      strokeStyle: colors.main,
      lineWidth: 1,
    };
    const body = Matter.Bodies.circle(pos.x, pos.y, part.radius, {
      label: partBodyLabel(meta),
      collisionFilter: { group },
      render: style,
      restitution: 0,
      friction: 0.85,
      frictionAir: 0.02,
    });
    applyPartRender(body, meta);
    if (meta.spike) {
      body.plugin = { ...(body.plugin ?? {}), spikeWeapon: true };
    }
    bodies.push(body);
  }

  const constraints: Matter.Constraint[] = [];

  for (const { a, b, type } of def.links) {
    const bodyA = bodies[a];
    const bodyB = bodies[b];
    if (!(bodyA && bodyB)) continue;
    constraints.push(...createLinkConstraints(defaultLinkType(type), bodyA, bodyB));
  }

  const composite = Composite.create({
    bodies,
    constraints,
    label: "Monster",
  });

  for (const constraint of composite.constraints) {
    constraint.render.visible = false;
  }

  const head = bodies.find((b) => b.label === "Head");

  return {
    composite,
    head,
    maxHp: resolveMonsterMaxHp(def),
    colors,
  };
}

/** Прогрев constraint-сolver перед боем — меньше «взрыва» на первом кадре. */
export function settleComposite(
  composite: Composite,
  steps = 48,
  gravity = BATTLE_GRAVITY,
): void {
  const engine = Matter.Engine.create({ gravity });
  Matter.World.add(engine.world, composite);
  for (const body of composite.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }
  const delta = 1000 / 60;
  for (let i = 0; i < steps; i++) {
    updateMonsterRopeConstraints(composite);
    Matter.Engine.update(engine, delta);
  }
  for (const body of composite.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }
  Matter.World.clear(engine.world, false);
  Matter.Engine.clear(engine);
}

/** Снимок позиций из собранного composite → MonsterDef (относительные coords). */
export function snapshotMonsterFromComposite(
  composite: Composite,
  meta: { isHead: boolean; role?: import("./monsterTypes").MonsterPartRole }[],
  links: { a: number; b: number; type?: import("./linkTypes").MonsterLinkType }[],
  name: string,
  id?: string,
  stats?: import("./monsterTypes").MonsterStats,
): MonsterDef {
  const positions = composite.bodies.map((b) => Vector.create(b.position.x, b.position.y));
  const center = positions.reduce(
    (acc, p) => Vector.add(acc, p),
    Vector.create(0, 0),
  );
  const c = Vector.div(center, positions.length);

  const parts = composite.bodies.map((body, index) => ({
    x: body.position.x - c.x,
    y: body.position.y - c.y,
    radius: body.circleRadius ?? 10,
    isHead: meta[index]?.isHead ?? body.label === "Head",
    role: meta[index]?.role ?? (body.label === "Armor" ? "armor" : "hurtbox"),
  }));

  return {
    id: id ?? crypto.randomUUID(),
    name,
    parts,
    links: links.map((l) => ({ ...l })),
    stats,
    createdAt: Date.now(),
  };
}
