import Matter, { type Body, type Composite } from "matter-js";
import { createLinkConstraints } from "@/monster/linkTypes";
import type { ItemDef } from "./registry";

const ITEM_GROUP = Matter.Body.nextGroup(true);

export function buildItem(
  def: ItemDef,
  x: number,
  y: number,
): Composite {
  const bodies = def.bodies.map((spec, index) => {
    const body = Matter.Bodies.circle(spec.x + x, spec.y + y, spec.radius, {
      label: spec.grip ? "Grip" : spec.label ?? "ItemPart",
      friction: 0.9,
      restitution: 0.1,
      density: 0.002,
      collisionFilter: {
        group: ITEM_GROUP,
        category: 0x0004,
        mask: 0xffff,
      },
      render: spec.render ?? { fillStyle: "#888" },
    });
    const plugin = (body.plugin ?? {}) as Record<string, unknown>;
    plugin.itemId = def.id;
    plugin.itemPartIndex = index;
    if (spec.grip) plugin.gripOf = def.id;
    body.plugin = plugin;
    return body;
  });

  const constraints = def.links.flatMap((link) => {
    const bodyA = bodies[link.from];
    const bodyB = bodies[link.to];
    if (!bodyA || !bodyB) {
      throw new Error(`Invalid link in item ${def.id}`);
    }
    return createLinkConstraints(link.type, bodyA, bodyB);
  });

  for (const c of constraints) {
    c.render.visible = false;
  }

  return Matter.Composite.create({
    bodies,
    constraints,
    label: def.name,
  });
}

export function tagItemOwner(
  composite: Composite,
  ownerFighterId: string | null,
): void {
  for (const body of composite.bodies) {
    const plugin = (body.plugin ?? {}) as Record<string, unknown>;
    if (ownerFighterId) plugin.ownerFighterId = ownerFighterId;
    else delete plugin.ownerFighterId;
    body.plugin = plugin;
  }
}

export function findItemComposite(
  body: Body,
  composites: Composite[],
): Composite | undefined {
  const itemId = (body.plugin as { itemId?: string })?.itemId;
  if (!itemId) return undefined;
  return composites.find((c) =>
    c.bodies.some(
      (b) => (b.plugin as { itemId?: string })?.itemId === itemId,
    ),
  );
}
