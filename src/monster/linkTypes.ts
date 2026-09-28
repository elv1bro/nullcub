import Matter, {
  type Body,
  type Composite,
  type Constraint,
  type IConstraintDefinition,
} from "matter-js";

export type MonsterLinkType = "rigid" | "spring" | "rope";

export const LINK_TYPE_ORDER: MonsterLinkType[] = ["rigid", "spring", "rope"];

export const LINK_COLORS: Record<MonsterLinkType, string> = {
  rigid: "#38bdf8",
  spring: "#a78bfa",
  rope: "#fbbf24",
};

const ROPE_SLACK_MULT = 1.08;
const ROPE_SLACK_STIFFNESS = 0.01;
const ROPE_TIGHT_STIFFNESS = 0.96;
/** Пружина: достаточно жёсткая, чтобы не расползаться под AI dash/flip. */
export const SPRING_STIFFNESS = 0.62;
export const SPRING_DAMPING = 0.12;

type LinkPlugin = { monsterLinkType?: MonsterLinkType };

/** Полуразмер тела вдоль направления (круг или AABB-прямоугольник). */
export function bodyExtentAlong(body: Body, dir: Matter.Vector): number {
  if (body.circleRadius != null && body.circleRadius > 0) {
    return body.circleRadius;
  }
  const hw = Math.max(1, (body.bounds.max.x - body.bounds.min.x) / 2);
  const hh = Math.max(1, (body.bounds.max.y - body.bounds.min.y) / 2);
  // Локальные оси с учётом угла тела.
  const local = Matter.Vector.rotate(dir, -body.angle);
  const nx = Math.abs(local.x);
  const ny = Math.abs(local.y);
  const len = Math.hypot(nx, ny) || 1;
  return (nx / len) * hw + (ny / len) * hh;
}

/** Якоря на поверхности тел + длина «край–край» в текущей позе. */
export function linkAnchors(bodyA: Body, bodyB: Body) {
  const delta = Matter.Vector.sub(bodyB.position, bodyA.position);
  const dist = Matter.Vector.magnitude(delta);

  if (dist < 1e-4) {
    return {
      pointA: { x: 0, y: 0 },
      pointB: { x: 0, y: 0 },
      restLength: 0,
    };
  }

  const dir = Matter.Vector.div(delta, dist);
  const rA = bodyExtentAlong(bodyA, dir);
  const rB = bodyExtentAlong(bodyB, Matter.Vector.neg(dir));
  return {
    pointA: Matter.Vector.create(dir.x * rA, dir.y * rA),
    pointB: Matter.Vector.create(-dir.x * rB, -dir.y * rB),
    restLength: Math.max(0, dist - rA - rB),
  };
}

function bodyWorldPoint(body: Body, point: Matter.Vector): Matter.Vector {
  return Matter.Vector.add(body.position, Matter.Vector.rotate(point, body.angle));
}

export function constraintSpan(c: Constraint): number {
  if (!(c.bodyA && c.bodyB)) return 0;
  const worldA = bodyWorldPoint(c.bodyA, c.pointA);
  const worldB = bodyWorldPoint(c.bodyB, c.pointB);
  return Matter.Vector.magnitude(Matter.Vector.sub(worldB, worldA));
}

function tagConstraint(c: Constraint, type: MonsterLinkType): void {
  const plugin = (c.plugin ?? {}) as LinkPlugin;
  plugin.monsterLinkType = type;
  c.plugin = plugin;
}

export function linkConstraintOptions(
  type: MonsterLinkType,
  bodyA: Body,
  bodyB: Body,
): IConstraintDefinition {
  const { pointA, pointB, restLength } = linkAnchors(bodyA, bodyB);
  const base = {
    bodyA,
    bodyB,
    pointA,
    pointB,
    render: {
      visible: true,
      lineWidth: 3,
      strokeStyle: LINK_COLORS[type],
    },
  };

  switch (type) {
    case "spring":
      return {
        ...base,
        stiffness: SPRING_STIFFNESS,
        damping: SPRING_DAMPING,
        length: restLength,
      };
    case "rope":
      return {
        ...base,
        stiffness: ROPE_SLACK_STIFFNESS,
        damping: 0.04,
        length: restLength * ROPE_SLACK_MULT,
      };
    default:
      return {
        ...base,
        stiffness: 1,
        damping: 0.03,
        length: restLength,
      };
  }
}

/** Одна или две constraint — как у stickman для жёстких связей. */
export function createLinkConstraints(
  type: MonsterLinkType,
  bodyA: Body,
  bodyB: Body,
): Constraint[] {
  const primary = Matter.Constraint.create(
    linkConstraintOptions(type, bodyA, bodyB),
  );
  tagConstraint(primary, type);

  if (type !== "rigid") {
    return [primary];
  }

  const { pointA, pointB } = linkAnchors(bodyA, bodyB);
  const secondary = Matter.Constraint.create({
    bodyA,
    bodyB,
    pointA: { x: -pointA.y * 0.4, y: pointA.x * 0.4 },
    pointB: { x: -pointB.y * 0.4, y: pointB.x * 0.4 },
    stiffness: 0.82,
    damping: 0.04,
    length: 0,
    render: { visible: false },
  });
  tagConstraint(secondary, "rigid");
  return [primary, secondary];
}

/** Пересобрать все связи по текущим позициям частей. */
export function rebuildCompositeLinks(
  composite: Composite,
  links: { a: number; b: number; type: MonsterLinkType }[],
): void {
  for (const c of [...composite.constraints]) {
    Matter.Composite.remove(composite, c);
  }

  for (const link of links) {
    const bodyA = composite.bodies[link.a];
    const bodyB = composite.bodies[link.b];
    if (!(bodyA && bodyB)) continue;

    for (const c of createLinkConstraints(link.type, bodyA, bodyB)) {
      c.render.visible = false;
      Matter.Composite.add(composite, c);
    }
  }
}

/** Верёвка: тянет только при перерастяжении, иначе провисает. */
export function updateMonsterRopeConstraints(composite: Composite): void {
  for (const c of composite.constraints) {
    if ((c.plugin as LinkPlugin | undefined)?.monsterLinkType !== "rope") {
      continue;
    }
    if (!(c.bodyA && c.bodyB)) continue;

    const { restLength } = linkAnchors(c.bodyA, c.bodyB);
    const maxLength = Math.max(4, restLength * ROPE_SLACK_MULT);
    const span = constraintSpan(c);

    if (span <= maxLength) {
      c.stiffness = ROPE_SLACK_STIFFNESS;
      c.length = maxLength;
    } else {
      c.stiffness = ROPE_TIGHT_STIFFNESS;
      c.length = maxLength;
    }
  }
}

export function defaultLinkType(type?: MonsterLinkType): MonsterLinkType {
  return type ?? "rigid";
}
