import Matter, { type Body, type Composite } from "matter-js";
import { createLinkConstraints, LINK_COLORS } from "@/monster/linkTypes";
import { getDamageType } from "./damageTypes";
import type {
  ItemBodySpec,
  ItemDef,
  SolidWeaponPart,
  SolidWeaponSpec,
} from "./registry";

const ITEM_CATEGORY = 0x0004;

function buildPartBody(
  spec: ItemBodySpec,
  ox: number,
  oy: number,
  group: number,
): Body {
  const x = spec.x + ox;
  const y = spec.y + oy;
  const common = {
    label: spec.grip ? "Grip" : spec.label ?? "ItemPart",
    friction: 0.85,
    frictionAir: 0.04,
    restitution: 0.08,
    density: spec.grip ? 0.0012 : 0.0024,
    collisionFilter: {
      group,
      category: ITEM_CATEGORY,
      mask: 0xffff,
    },
    render: {
      fillStyle: spec.render?.fillStyle ?? "#888",
      strokeStyle: spec.render?.strokeStyle ?? "#111",
      lineWidth: spec.render?.lineWidth ?? 1.5,
      visible: true,
    },
  };

  if (spec.width != null && spec.height != null) {
    return Matter.Bodies.rectangle(x, y, spec.width, spec.height, common);
  }
  return Matter.Bodies.circle(x, y, spec.radius ?? 8, common);
}

function tagWeaponBody(
  body: Body,
  def: ItemDef,
  gripLocal: { x: number; y: number },
  mass: number,
): void {
  const plugin = (body.plugin ?? {}) as Record<string, unknown>;
  plugin.itemId = def.id;
  plugin.gripOf = def.id;
  plugin.gripLocal = { ...gripLocal };
  plugin.weaponMass = mass;
  plugin.itemSolid = true;
  body.plugin = plugin;
}

/** Все физические тела оружия (без parent-дубля compound). */
export function itemLeafBodies(composite: Composite): Body[] {
  const out: Body[] = [];
  for (const b of composite.bodies) {
    if (b.parts && b.parts.length > 1) {
      for (const p of b.parts) {
        if (p !== b) out.push(p);
      }
    } else {
      out.push(b);
    }
  }
  return out;
}

/** Тело, к которому можно вешать Matter.Constraint (parent, не part). */
export function resolveConstraintBody(body: Body): Body {
  if (body.parent && body.parent !== body) return body.parent;
  return body;
}

function solidPartBody(
  part: SolidWeaponPart,
  ox: number,
  oy: number,
  stroke: string,
): Body {
  const common = {
    label: part.label ?? "ItemPart",
    friction: 0.9,
    frictionAir: 0.02,
    restitution: 0.05,
    density: 0.002,
    collisionFilter: {
      group: 0,
      category: ITEM_CATEGORY,
      mask: 0xffff,
    },
    render: {
      fillStyle: part.color,
      strokeStyle: part.stroke ?? stroke,
      lineWidth: 1.5,
      visible: true,
    },
  };
  const x = ox + part.x;
  const y = oy + part.y;
  let body: Body;
  if (part.w != null && part.h != null) {
    body = Matter.Bodies.rectangle(x, y, part.w, part.h, common);
  } else {
    body = Matter.Bodies.circle(x, y, part.r ?? 8, common);
  }
  if (part.angle) {
    Matter.Body.setAngle(body, part.angle);
  }
  return body;
}

function buildSolidWeapon(
  def: ItemDef,
  solid: SolidWeaponSpec,
  x: number,
  y: number,
): Composite {
  const dtype = getDamageType(def.damageType);
  const fill = solid.color || dtype.color || "#94a3b8";
  const stroke = solid.stroke ?? "#0f172a";
  const mass = Math.max(0.35, solid.mass);

  // Design-origin = (x, y). gripLocal и parts в одной системе.
  const designGrip = {
    x: x + solid.gripLocal.x,
    y: y + solid.gripLocal.y,
  };

  let body: Body;

  if (solid.parts && solid.parts.length > 0) {
    const parts = solid.parts.map((p) => solidPartBody(p, x, y, stroke));
    body = Matter.Body.create({
      parts,
      label: "Grip",
      friction: 0.9,
      frictionAir: 0.02,
      restitution: 0.05,
      collisionFilter: {
        group: 0,
        category: ITEM_CATEGORY,
        mask: 0xffff,
      },
      render: {
        fillStyle: fill,
        strokeStyle: stroke,
        lineWidth: 2,
        visible: true,
      },
    });
  } else if (solid.shape === "circle") {
    const r = solid.radius ?? Math.max(10, solid.thickness);
    body = Matter.Bodies.circle(x, y, r, {
      label: "Grip",
      friction: 0.9,
      frictionAir: 0.02,
      restitution: 0.05,
      collisionFilter: {
        group: 0,
        category: ITEM_CATEGORY,
        mask: 0xffff,
      },
      render: {
        fillStyle: fill,
        strokeStyle: stroke,
        lineWidth: 2,
        visible: true,
      },
    });
  } else {
    body = Matter.Bodies.rectangle(x, y, solid.length, solid.thickness, {
      label: "Grip",
      friction: 0.9,
      frictionAir: 0.02,
      restitution: 0.05,
      collisionFilter: {
        group: 0,
        category: ITEM_CATEGORY,
        mask: 0xffff,
      },
      render: {
        fillStyle: fill,
        strokeStyle: stroke,
        lineWidth: 2,
        visible: true,
      },
    });
  }

  // Body.create сдвигает COM — grip относительно фактического центра.
  const gripLocal = {
    x: designGrip.x - body.position.x,
    y: designGrip.y - body.position.y,
  };

  Matter.Body.setMass(body, mass);
  Matter.Body.setInertia(
    body,
    Math.max(body.inertia, body.mass * (solid.length ** 2) * 0.08),
  );

  tagWeaponBody(body, def, gripLocal, mass);
  if (body.parts && body.parts.length > 1) {
    for (const p of body.parts) {
      if (p === body) continue;
      tagWeaponBody(p, def, gripLocal, mass);
    }
  }

  return Matter.Composite.create({
    bodies: [body],
    label: def.name,
  });
}

/** Верёвочное / составное (flail, whip) — отдельные тела + constraints. */
function buildLinkedWeapon(def: ItemDef, x: number, y: number): Composite {
  const group = Matter.Body.nextGroup(true);
  const bodies = def.bodies.map((spec, index) => {
    const body = buildPartBody(spec, x, y, group);
    const plugin = (body.plugin ?? {}) as Record<string, unknown>;
    plugin.itemId = def.id;
    plugin.itemPartIndex = index;
    if (spec.grip) plugin.gripOf = def.id;
    body.plugin = plugin;
    return body;
  });

  const dtype = getDamageType(def.damageType);
  const shaftColor = dtype.color ?? LINK_COLORS.rigid;

  const constraints = def.links.flatMap((link) => {
    const bodyA = bodies[link.from];
    const bodyB = bodies[link.to];
    if (!bodyA || !bodyB) {
      throw new Error(`Invalid link in item ${def.id}`);
    }
    const created = createLinkConstraints(link.type, bodyA, bodyB);
    for (const c of created) {
      if (c.render.visible === false) continue;
      c.render.visible = true;
      c.render.lineWidth = link.type === "rope" ? 2.5 : 5;
      c.render.strokeStyle =
        link.type === "rope" ? "#a8a29e" : shaftColor;
    }
    return created;
  });

  return Matter.Composite.create({
    bodies,
    constraints,
    label: def.name,
  });
}

export function buildItem(def: ItemDef, x: number, y: number): Composite {
  if (def.solid) {
    return buildSolidWeapon(def, def.solid, x, y);
  }
  if (!def.bodies.length) {
    throw new Error(`Item ${def.id} has neither solid nor bodies`);
  }
  return buildLinkedWeapon(def, x, y);
}

export function tagItemOwner(
  composite: Composite,
  ownerFighterId: string | null,
): void {
  const apply = (body: Body) => {
    const plugin = (body.plugin ?? {}) as Record<string, unknown>;
    if (ownerFighterId) plugin.ownerFighterId = ownerFighterId;
    else delete plugin.ownerFighterId;
    body.plugin = plugin;
  };
  for (const body of composite.bodies) {
    apply(body);
    if (body.parts && body.parts.length > 1) {
      for (const p of body.parts) apply(p);
    }
  }
}

export function findItemComposite(
  body: Body,
  composites: Composite[],
): Composite | undefined {
  const root = resolveConstraintBody(body);
  const itemId =
    (body.plugin as { itemId?: string })?.itemId ??
    (root.plugin as { itemId?: string })?.itemId;
  if (!itemId) return undefined;
  return composites.find(
    (c) =>
      c.bodies.some(
        (b) => (b.plugin as { itemId?: string })?.itemId === itemId,
      ) ||
      itemLeafBodies(c).some(
        (b) => (b.plugin as { itemId?: string })?.itemId === itemId,
      ),
  );
}

/** Масса удерживаемого оружия (0 если нет). */
export function weaponMassOf(composite: Composite): number {
  for (const b of composite.bodies) {
    const m = (b.plugin as { weaponMass?: number })?.weaponMass;
    if (typeof m === "number" && m > 0) return m;
  }
  for (const b of itemLeafBodies(composite)) {
    const m = (b.plugin as { weaponMass?: number })?.weaponMass;
    if (typeof m === "number" && m > 0) return m;
  }
  let sum = 0;
  for (const b of itemLeafBodies(composite)) sum += b.mass;
  return sum;
}

/**
 * Штраф к скорости бега от массы оружия в руках.
 * Лёгкий кинжал ~0.95, меч ~0.78, ядро ~0.5.
 */
export function weaponHoldMoveMult(mass: number): number {
  if (mass <= 0) return 1;
  return Math.max(0.42, Math.min(0.97, 1.05 - mass * 0.16));
}
