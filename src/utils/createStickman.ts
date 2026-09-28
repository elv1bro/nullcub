//

import defaults from "defaults";
import Matter, { Body, Vector, type Constraint } from "matter-js";

// Порт onedoes/ragdollmasters + зеркальная симметрия L/R.
// Без симметрии idle за ~10с валится вправо (разные rest-length связей).

interface BodyPartOptions {
  x: number;
  y: number;
  radius: number;
  length?: number;
  options?: Matter.IBodyDefinition;
  constraint?: Matter.IConstraintDefinition;
}

function createStick(_options: BodyPartOptions) {
  const { x, y, radius, length = 2, constraint, options } = _options;
  const { bodies } = Matter.Composites.stack(
    x,
    y,
    length,
    1,
    0,
    0,
    (x: number, y: number) => {
      return Matter.Bodies.circle(x, y, radius, options);
    }
  );

  const constraints = Array.from(bodies.entries())
    .filter(([bodyId]) => bodyId > 0)
    .map(([bodyId, bodyB]) => ({
      ...constraint,
      bodyA: bodies[bodyId - 1]!,
      bodyB,
      damping: 0,
      stiffness: 1,
    }))
    .flatMap((common) => [
      Matter.Constraint.create({
        ...common,
      }),
      Matter.Constraint.create({
        ...common,
        pointA: { x: radius, y: 0 },
        pointB: { x: -radius, y: 0 },
        damping: 0,
        length: 0,
        stiffness: 0.5,
      }),
    ]);

  return { bodies, constraints };
}

function createBody(_options: BodyPartOptions) {
  const { x, y, radius, constraint, options } = _options;
  const { bodies } = Matter.Composites.stack(
    x,
    y,
    1,
    4,
    0,
    0,
    (x: number, y: number) => {
      return Matter.Bodies.circle(x, y, radius, options);
    }
  );
  const constraints = Array.from(bodies.entries())
    .filter(([bodyId]) => bodyId > 0)
    .map(([bodyId, bodyB]) => ({
      ...constraint,
      bodyA: bodies[bodyId - 1]!,
      bodyB,
      damping: 0,
      stiffness: 1,
    }))
    .flatMap((common) => [
      Matter.Constraint.create({
        ...common,
      }),
      Matter.Constraint.create({
        ...common,
        pointA: { x: 0, y: radius },
        pointB: { x: 0, y: -radius },
        damping: 0,
        length: 0,
        stiffness: 0.5,
      }),
    ]);
  return { bodies, constraints };
}

/** Вертикальная цепочка сегментов (ноги вниз, без T-pose + fold). */
function createVerticalStick(_options: BodyPartOptions) {
  const { x, y, radius, length = 3, constraint, options } = _options;
  const { bodies } = Matter.Composites.stack(
    x,
    y,
    1,
    length,
    0,
    0,
    (sx: number, sy: number) => Matter.Bodies.circle(sx, sy, radius, options),
  );
  const constraints = Array.from(bodies.entries())
    .filter(([bodyId]) => bodyId > 0)
    .map(([bodyId, bodyB]) => ({
      ...constraint,
      bodyA: bodies[bodyId - 1]!,
      bodyB,
      damping: 0,
      stiffness: 1,
    }))
    .flatMap((common) => [
      Matter.Constraint.create({
        ...common,
      }),
      Matter.Constraint.create({
        ...common,
        pointA: { x: 0, y: radius },
        pointB: { x: 0, y: -radius },
        damping: 0,
        length: 0,
        stiffness: 0.5,
      }),
    ]);
  return { bodies, constraints };
}

export function createStickman(
  x: number,
  y: number,
  options?: Partial<{
    scale: number;
    render: Matter.IBodyRenderOptions;
    bodyDef: Matter.IBodyDefinition;
  }>
): Matter.Composite {
  const { scale, render } = defaults(options ?? ({} as any), {
    scale: 1,
    render: {},
  });

  const radius = 10 * scale;
  const flex = 1 / 10_000;

  //
  // HEAD
  //

  const head_group = Matter.Body.nextGroup(true);
  const head = Matter.Bodies.circle(x, y - 3 * radius, 2 * radius, {
    label: "Head",
    collisionFilter: {
      group: head_group,
    },
    render,
    restitution: 0,
    friction: 0.1,
    frictionAir: 0.01,
  });

  //#region Chest

  //
  // CHEST
  //

  // Matter.Composites.stack потом делает translate(+radius, +radius) —
  // поэтому старт x-radius → центр груди ровно на x.
  const chest = createBody({
    x: x - radius,
    y: y - radius,
    radius: radius,
    options: {
      label: "Chest",
      collisionFilter: {
        group: Matter.Body.nextGroup(true),
      },
      render,
      friction: 0.1,
      frictionAir: 0.01,
      restitution: 0,
    },
    constraint: { stiffness: 1, damping: 0 },
  });
  // chest.bodies.at(0)!.collisionFilter.group = head_group;

  const head_x_chest = [
    Matter.Constraint.create({
      bodyA: head,
      pointA: { x: 0, y: radius * 2 },
      bodyB: chest.bodies.at(0),
      pointB: { x: 0, y: -radius },
      stiffness: 1,
      damping: 0,
    }),
    Matter.Constraint.create({
      bodyA: chest.bodies.at(-1),
      bodyB: chest.bodies.at(0),
      stiffness: 1 / 1_000,
    }),
  ];

  //#endregion

  const arm_group = Matter.Body.nextGroup(true);
  //#region Left Arm

  //
  // Left Arm
  //

  // Upper Left Arm

  const upperLeftArm = createStick({
    x: x - radius * 5,
    y: y - radius,
    radius: radius,
    options: {
      label: "Upper Left Arm",
      collisionFilter: {
        group: arm_group,
      },
      render,
      restitution: 0,
      friction: 0.1,
    },
  });

  const upperLeftArm_x_body = [
    Matter.Constraint.create({
      bodyA: upperLeftArm.bodies.at(-1),
      bodyB: chest.bodies.at(0),
      stiffness: 1,
      damping: 0,
    }),
    Matter.Constraint.create({
      bodyA: upperLeftArm.bodies.at(-1),
      pointA: { x: radius, y: 0 },
      bodyB: chest.bodies.at(0),
      pointB: { x: -radius, y: 0 },
      damping: 0,
      length: 0,
      stiffness: 1,
    }),
  ];

  // Lower Left Arm

  const lowerLeftArm = createStick({
    x: x - radius * 11,
    length: 3,
    y: y - radius,
    radius: radius,
    options: {
      label: "Lower Left Arm",
      render,
      collisionFilter: {
        group: arm_group,
      },
      restitution: 0,
      friction: 0.1,
    },
  });

  const upperLeftArm_x_lowerLeftArm = [
    Matter.Constraint.create({
      bodyA: upperLeftArm.bodies.at(0),
      bodyB: lowerLeftArm.bodies.at(0),
      damping: 0,
      stiffness: 1,
    }),
    Matter.Constraint.create({
      bodyA: upperLeftArm.bodies.at(-1),
      bodyB: lowerLeftArm.bodies.at(-1),
      damping: 0,
      stiffness: 1,
    }),
    Matter.Constraint.create({
      bodyA: upperLeftArm.bodies.at(0),
      pointA: { x: -radius, y: 0 },
      bodyB: lowerLeftArm.bodies.at(-1),
      pointB: { x: radius, y: 0 },
      damping: 0,
      length: 0,
      stiffness: 1,
    }),
  ];

  //#endregion

  //#region Right Arm

  //
  // RIGHT ARM
  //

  // Зеркало left upper: stack сдвигает на +r, поэтому старт x+r → центры x+2r, x+4r
  // (left при старте x-5r → x-4r, x-2r).
  const upperRightArm = createStick({
    x: x + radius,
    y: y - radius,
    radius: radius,
    options: {
      label: "Upper Right Arm",
      collisionFilter: {
        group: arm_group,
      },
      render,
      friction: 0.1,
      restitution: 0,
    },
  });

  const upperRightArm_x_body = [
    Matter.Constraint.create({
      bodyA: upperRightArm.bodies.at(0),
      bodyB: chest.bodies.at(0),
      damping: 0,
      stiffness: 1,
    }),
    Matter.Constraint.create({
      bodyA: chest.bodies.at(0),
      pointA: { x: radius, y: 0 },
      bodyB: upperRightArm.bodies.at(0),
      pointB: { x: -radius, y: 0 },
      damping: 0,
      length: 0,
      stiffness: 1,
    }),
  ];

  //

  // Зеркало left lower (старт x-11r → центры x-10r…x-6r): старт x+5r → x+6r…x+10r.
  const lowerRightArm = createStick({
    x: x + radius * 5,
    y: y - radius,
    length: 3,
    radius: radius,
    options: {
      label: "Lower Right Arm",
      collisionFilter: {
        group: arm_group,
      },
      render,
      friction: 0.1,
      restitution: 0,
    },
  });

  const upperRightArm_x_lowerRightArm = [
    Matter.Constraint.create({
      bodyA: upperRightArm.bodies.at(0),
      bodyB: lowerRightArm.bodies.at(0),
      damping: 0,
      stiffness: 1,
    }),
    Matter.Constraint.create({
      bodyA: upperRightArm.bodies.at(-1),
      bodyB: lowerRightArm.bodies.at(-1),
      damping: 0,
      stiffness: 1,
    }),
    Matter.Constraint.create({
      bodyA: upperRightArm.bodies.at(-1),
      pointA: { x: radius, y: 0 },
      bodyB: lowerRightArm.bodies.at(0),
      pointB: { x: -radius, y: 0 },
      damping: 0,
      length: 0,
      stiffness: 1,
    }),
  ];

  //#endregion

  const head_x_arms = [
    Matter.Constraint.create({
      bodyA: head,
      bodyB: upperRightArm.bodies.at(0),
      stiffness: flex,
      // damping: 0,
      // length: radius * 8,
    }),
    Matter.Constraint.create({
      bodyA: head,
      bodyB: upperLeftArm.bodies.at(-1),
      stiffness: flex,
      // damping: 0,
      // length: radius * 8,
    }),
  ];

  // Одна negative-группа на все сегменты ног — иначе голени сталкиваются и «спутываются».
  const leg_group = Matter.Body.nextGroup(true);
  const hip = chest.bodies.at(-1)!;
  // Ширина стойки: левая нога левее центра, правая правее (не перекрёст).
  const hipStance = radius * 2;
  const legTopY = hip.position.y + radius * 0.5;

  //#region Left Leg (вертикально вниз)

  // stack +translate(+r,+r): старт (x ± hipStance - r) → центр ноги на x ± hipStance.
  const upperLeftLeg = createVerticalStick({
    x: x - hipStance - radius,
    y: legTopY,
    length: 3,
    radius,
    options: {
      label: "Upper Left Leg",
      collisionFilter: { group: leg_group },
      render,
      restitution: 0,
      friction: 0.1,
    },
  });

  const upperLeftLeg_x_body = [
    Matter.Constraint.create({
      bodyA: upperLeftLeg.bodies.at(0),
      pointA: { x: 0, y: -radius },
      bodyB: hip,
      pointB: { x: -radius, y: radius },
      stiffness: 1,
      damping: 0,
      length: 0,
    }),
    Matter.Constraint.create({
      bodyA: hip,
      bodyB: upperLeftLeg.bodies.at(0),
      stiffness: 0.5,
      damping: 0,
      length: radius * 2,
    }),
  ];

  const lowerLeftLeg = createVerticalStick({
    x: x - hipStance - radius,
    y: legTopY + radius * 6,
    length: 3,
    radius,
    options: {
      label: "Lower Left Leg",
      collisionFilter: { group: leg_group },
      render,
      restitution: 0,
      friction: 0.1,
    },
  });

  const upperLeftLeg_x_lowerLeftLeg = [
    Matter.Constraint.create({
      bodyA: upperLeftLeg.bodies.at(-1),
      bodyB: lowerLeftLeg.bodies.at(0),
      stiffness: 1,
      damping: 0,
    }),
    Matter.Constraint.create({
      bodyA: upperLeftLeg.bodies.at(-1),
      pointA: { x: 0, y: radius },
      bodyB: lowerLeftLeg.bodies.at(0),
      pointB: { x: 0, y: -radius },
      stiffness: 1,
      damping: 0,
      length: 0,
    }),
  ];
  //#endregion

  //#region Right Leg (вертикально вниз)

  const upperRightLeg = createVerticalStick({
    x: x + hipStance - radius,
    y: legTopY,
    length: 3,
    radius,
    options: {
      label: "Upper Right Leg",
      collisionFilter: { group: leg_group },
      render,
      restitution: 0,
      friction: 0.1,
    },
  });

  const upperRightLeg_x_body = [
    Matter.Constraint.create({
      bodyA: upperRightLeg.bodies.at(0),
      pointA: { x: 0, y: -radius },
      bodyB: hip,
      pointB: { x: radius, y: radius },
      stiffness: 1,
      damping: 0,
      length: 0,
    }),
    Matter.Constraint.create({
      bodyA: hip,
      bodyB: upperRightLeg.bodies.at(0),
      stiffness: 0.5,
      damping: 0,
      length: radius * 2,
    }),
  ];

  const lowerRightLeg = createVerticalStick({
    x: x + hipStance - radius,
    y: legTopY + radius * 6,
    length: 3,
    radius,
    options: {
      label: "Lower Right Leg",
      collisionFilter: { group: leg_group },
      render,
      restitution: 0,
      friction: 0.1,
    },
  });

  const upperRightLeg_x_lowerRightLeg = [
    Matter.Constraint.create({
      bodyA: upperRightLeg.bodies.at(-1),
      bodyB: lowerRightLeg.bodies.at(0),
      stiffness: 1,
      damping: 0,
    }),
    Matter.Constraint.create({
      bodyA: upperRightLeg.bodies.at(-1),
      pointA: { x: 0, y: radius },
      bodyB: lowerRightLeg.bodies.at(0),
      pointB: { x: 0, y: -radius },
      stiffness: 1,
      damping: 0,
      length: 0,
    }),
  ];

  //#endregion

  // Распорка бёдер: держит ширину стойки (НЕ length:0 — иначе ноги стягивает в одну точку).
  const hipWidth = hipStance * 2;
  const upperLeftLeg_x_upperRightLeg = [
    Matter.Constraint.create({
      bodyA: upperRightLeg.bodies.at(0),
      bodyB: upperLeftLeg.bodies.at(0),
      stiffness: 0.8,
      damping: 0.05,
      length: hipWidth,
    }),
    Matter.Constraint.create({
      bodyA: upperRightLeg.bodies.at(1),
      bodyB: upperLeftLeg.bodies.at(1),
      stiffness: 1 / 5_000,
      damping: 1 / 1_000,
      length: hipWidth,
    }),
  ];

  //

  const composite = Matter.Composite.create({
    bodies: [
      head,
      ...chest.bodies,
      //
      ...upperLeftArm.bodies,
      ...lowerLeftArm.bodies,
      ...upperRightArm.bodies,
      ...lowerRightArm.bodies,
      //
      ...upperLeftLeg.bodies,
      ...lowerLeftLeg.bodies,
      ...upperRightLeg.bodies,
      ...lowerRightLeg.bodies,
    ],
    constraints: [
      ...head_x_chest,
      ...chest.constraints,
      //
      ...upperLeftArm_x_body,
      ...upperLeftArm.constraints,
      ...upperLeftArm_x_lowerLeftArm,
      ...lowerLeftArm.constraints,
      //
      ...upperRightArm_x_body,
      ...upperRightArm.constraints,
      ...upperRightArm_x_lowerRightArm,
      ...lowerRightArm.constraints,
      //
      ...head_x_arms,
      //
      ...upperLeftLeg_x_body,
      ...upperLeftLeg.constraints,
      ...upperLeftLeg_x_lowerLeftLeg,
      ...lowerLeftLeg.constraints,
      //
      ...upperRightLeg_x_body,
      ...upperRightLeg.constraints,
      ...upperRightLeg_x_lowerRightLeg,
      ...lowerRightLeg.constraints,
      //
      ...upperLeftLeg_x_upperRightLeg,
    ],
    label: "Stickman",
  });

  for (const constraint of composite.constraints) {
    constraint.render.visible = false;
  }

  // Дожимаем зеркальность и rest-length (stack Matter даёт float-погрешности).
  symmetrizeStickman(composite, x);

  return composite;
}

function bodiesByLabel(composite: Matter.Composite, label: string): Body[] {
  return composite.bodies.filter((b) => b.label === label);
}

/** Зеркалит left ← right относительно centerX и пересчитывает длины связей. */
export function symmetrizeStickman(
  composite: Matter.Composite,
  centerX: number,
): void {
  const head = bodiesByLabel(composite, "Head")[0];
  if (head) {
    Body.setPosition(head, { x: centerX, y: head.position.y });
    Body.setAngle(head, 0);
  }
  for (const chest of bodiesByLabel(composite, "Chest")) {
    Body.setPosition(chest, { x: centerX, y: chest.position.y });
    Body.setAngle(chest, 0);
  }

  // Arms: горизонтальные цепочки → зеркало outer↔outer (reverse index).
  // Legs: вертикальные top→bottom → тот же индекс.
  const limbPairs: Array<[string, string, "flip" | "same"]> = [
    ["Upper Left Arm", "Upper Right Arm", "flip"],
    ["Lower Left Arm", "Lower Right Arm", "flip"],
    ["Upper Left Leg", "Upper Right Leg", "same"],
    ["Lower Left Leg", "Lower Right Leg", "same"],
  ];

  for (const [leftLabel, rightLabel, mode] of limbPairs) {
    const left = bodiesByLabel(composite, leftLabel);
    const right = bodiesByLabel(composite, rightLabel);
    if (left.length === 0 || left.length !== right.length) continue;
    for (let i = 0; i < left.length; i++) {
      const src =
        mode === "flip" ? right[right.length - 1 - i]! : right[i]!;
      const dst = left[i]!;
      Body.setPosition(dst, {
        x: 2 * centerX - src.position.x,
        y: src.position.y,
      });
      Body.setAngle(dst, -src.angle);
      Body.setVelocity(dst, { x: 0, y: 0 });
      Body.setAngularVelocity(dst, 0);
    }
    for (const body of right) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }
  }

  for (const body of composite.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
    if (body.frictionAir === undefined || body.frictionAir === 0.01) {
      body.frictionAir = 0.01;
    }
  }

  refreshConstraintLengths(composite);
}

function worldPoint(body: Body, point: Matter.Vector): Matter.Vector {
  return Vector.add(body.position, Vector.rotate(point, body.angle));
}

function refreshConstraintLengths(composite: Matter.Composite): void {
  for (const c of composite.constraints as Constraint[]) {
    if (!(c.bodyA && c.bodyB)) continue;
    // Явные zero-length шарниры не трогаем.
    if (c.length === 0) continue;
    const a = worldPoint(c.bodyA, c.pointA);
    const b = worldPoint(c.bodyB, c.pointB);
    c.length = Vector.magnitude(Vector.sub(a, b));
  }
}
