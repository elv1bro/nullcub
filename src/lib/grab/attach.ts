import Matter, { Body, Vector, type Body as MatterBody, type Composite, type Constraint, type Engine } from "matter-js";
import { grabPlugin, type GrabTargetRef } from "./types";

const WALL_STIFFNESS = 0.12;
const DYNAMIC_STIFFNESS = 0.32;
const CONSTRAINT_DAMPING = 0.18;

/** Смягчает импульс сразу после прилипания — иначе ragdoll «выстреливает». */
export function dampGrabBodies(hand: MatterBody, target: MatterBody | null): void {
  Body.setVelocity(hand, Vector.mult(hand.velocity, 0.4));
  Body.setAngularVelocity(hand, hand.angularVelocity * 0.4);
  if (target && !target.isStatic) {
    Body.setVelocity(target, Vector.mult(target.velocity, 0.55));
    Body.setAngularVelocity(target, target.angularVelocity * 0.55);
  }
}

export function createGrabPin(
  engine: Engine,
  hand: MatterBody,
  target: MatterBody,
  targetKind: GrabTargetRef["kind"],
  contactPoint?: Matter.Vector,
): Constraint[] {
  const worldPoint =
    contactPoint ??
    Matter.Vector.add(
      hand.position,
      Matter.Vector.div(Matter.Vector.sub(target.position, hand.position), 2),
    );

  const pointA = Matter.Vector.rotate(
    Matter.Vector.sub(worldPoint, hand.position),
    -hand.angle,
  );

  let constraint: Constraint;

  if (target.isStatic || targetKind === "wall") {
    // Якорь в мировых координатах — стабильнее, чем pin к огромному static-телу стены.
    constraint = Matter.Constraint.create({
      bodyA: hand,
      pointA,
      pointB: { x: worldPoint.x, y: worldPoint.y },
      stiffness: WALL_STIFFNESS,
      damping: CONSTRAINT_DAMPING,
      length: 2,
      render: { visible: false },
    });
  } else {
    const pointB = Matter.Vector.rotate(
      Matter.Vector.sub(worldPoint, target.position),
      -target.angle,
    );
    constraint = Matter.Constraint.create({
      bodyA: hand,
      pointA,
      bodyB: target,
      pointB,
      stiffness: DYNAMIC_STIFFNESS,
      damping: CONSTRAINT_DAMPING,
      length: 0,
      render: { visible: false },
    });
  }

  Matter.World.add(engine.world, constraint);
  return [constraint];
}

export function removeGrabConstraints(
  engine: Engine,
  constraints: Constraint[],
): void {
  if (!constraints.length) return;
  Matter.World.remove(engine.world, constraints);
}

export function resolveGrabTarget(
  hand: Body,
  other: Body,
  compositeMap: Map<number, number>,
): GrabTargetRef | null {
  const handFighter = grabPlugin(hand).fighterId;
  const otherPlugin = grabPlugin(other);
  const handComp = compositeMap.get(hand.id);
  const otherComp = compositeMap.get(other.id);

  // Никогда не хватать своё тело / сегменты своего ragdoll.
  if (handComp !== undefined && handComp === otherComp) return null;
  if (
    handFighter &&
    otherPlugin.fighterId &&
    handFighter === otherPlugin.fighterId
  ) {
    return null;
  }

  if (other.isStatic) {
    return { bodyId: other.id, kind: "wall" };
  }

  if (other.label === "Grip" || otherPlugin.gripOf) {
    return {
      bodyId: other.id,
      compositeId: otherComp,
      kind: "grip",
    };
  }

  if (otherPlugin.itemId) {
    return {
      bodyId: other.id,
      compositeId: otherComp,
      kind: "item",
    };
  }

  if (
    otherPlugin.fighterId &&
    handFighter &&
    otherPlugin.fighterId !== handFighter
  ) {
    return {
      bodyId: other.id,
      compositeId: otherComp,
      kind: "fighter",
    };
  }

  if (handComp !== undefined && otherComp !== undefined && handComp !== otherComp) {
    return { bodyId: other.id, compositeId: otherComp, kind: "item" };
  }

  return null;
}

export function buildCompositeBodyMap(
  composites: Composite[],
): Map<number, number> {
  const map = new Map<number, number>();
  for (const composite of composites) {
    for (const body of composite.bodies) {
      map.set(body.id, composite.id);
    }
  }
  return map;
}

/** Слишком быстрое сближение + жёсткий pin = взрывной импульс. */
export function grabAttachClosingSpeed(hand: Body, other: Body): number {
  const normal = Vector.normalise(Vector.sub(other.position, hand.position));
  return (
    Vector.dot(hand.velocity, normal) - Vector.dot(other.velocity, normal)
  );
}

export const MAX_GRAB_ATTACH_CLOSING = 14;
