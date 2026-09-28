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
    const body = target.parent && target.parent !== target ? target.parent : target;
    Body.setVelocity(body, Vector.mult(body.velocity, 0.55));
    Body.setAngularVelocity(body, body.angularVelocity * 0.55);
  }
}

/** Matter: constraint только к parent compound, не к part. */
function pinTargetBody(target: MatterBody): MatterBody {
  if (target.parent && target.parent !== target) return target.parent;
  return target;
}

export function createGrabPin(
  engine: Engine,
  hand: MatterBody,
  target: MatterBody,
  targetKind: GrabTargetRef["kind"],
  contactPoint?: Matter.Vector,
  opts?: { stiffness?: number },
): Constraint[] {
  const bodyB = pinTargetBody(target);
  const worldPoint =
    contactPoint ??
    Matter.Vector.add(
      hand.position,
      Matter.Vector.div(Matter.Vector.sub(bodyB.position, hand.position), 2),
    );

  const pointA = Matter.Vector.rotate(
    Matter.Vector.sub(worldPoint, hand.position),
    -hand.angle,
  );

  let constraint: Constraint;
  const stiffness = opts?.stiffness ?? DYNAMIC_STIFFNESS;

  if (bodyB.isStatic || targetKind === "wall") {
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
      Matter.Vector.sub(worldPoint, bodyB.position),
      -bodyB.angle,
    );
    constraint = Matter.Constraint.create({
      bodyA: hand,
      pointA,
      bodyB,
      pointB,
      stiffness,
      damping: CONSTRAINT_DAMPING,
      length: 0,
      render: { visible: false },
    });
  }

  Matter.World.add(engine.world, constraint);
  return [constraint];
}

const WEAPON_GUIDE_STIFFNESS = 0.15;
const WEAPON_GUIDE_DAMPING = 0.22;

/**
 * Мягкая направляющая: proximal-точка на предплечье ↔ точка на рукояти.
 * Вместе с жёстким grip-pin держит оружие вдоль руки.
 */
export function createWeaponGuidePin(
  engine: Engine,
  hand: MatterBody,
  weapon: MatterBody,
  guideWorld: Matter.Vector,
  proximalWorld: Matter.Vector,
): Constraint {
  const bodyB = pinTargetBody(weapon);
  const pointA = Matter.Vector.rotate(
    Matter.Vector.sub(proximalWorld, hand.position),
    -hand.angle,
  );
  const pointB = Matter.Vector.rotate(
    Matter.Vector.sub(guideWorld, bodyB.position),
    -bodyB.angle,
  );
  const constraint = Matter.Constraint.create({
    bodyA: hand,
    pointA,
    bodyB,
    pointB,
    stiffness: WEAPON_GUIDE_STIFFNESS,
    damping: WEAPON_GUIDE_DAMPING,
    length: 0,
    render: { visible: false },
  });
  Matter.World.add(engine.world, constraint);
  return constraint;
}

/** Proximal-якорь на кисти: чуть к груди бойца. */
export function forearmProximalWorld(
  hand: MatterBody,
  fighterComposite: Composite,
): Matter.Vector {
  const chest =
    fighterComposite.bodies.find((b) => b.label === "Chest") ??
    fighterComposite.bodies.find((b) => /chest/i.test(b.label ?? ""));
  if (!chest) {
    return {
      x: hand.position.x,
      y: hand.position.y - 10,
    };
  }
  const dir = Vector.normalise(Vector.sub(chest.position, hand.position));
  return Vector.add(hand.position, Vector.mult(dir, 12));
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
      if (body.parts && body.parts.length > 1) {
        for (const part of body.parts) {
          if (part !== body) map.set(part.id, composite.id);
        }
      }
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
