import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { buildMonster } from "./buildMonster";
import {
  constraintSpan,
  createLinkConstraints,
  linkAnchors,
  linkConstraintOptions,
  rebuildCompositeLinks,
  updateMonsterRopeConstraints,
} from "./linkTypes";
import { normalizeMonsterDef } from "./monsterTypes";
import { STARTER_MONSTERS } from "./starterMonsters";

const GRAVITY = { x: 0, y: 1 / 20, scale: 1 / 1000 };

describe("linkConstraintOptions", () => {
  it("uses edge-to-edge rest length, not zero", () => {
    const bodyA = Matter.Bodies.circle(100, 100, 20);
    const bodyB = Matter.Bodies.circle(160, 100, 12);
    const { restLength } = linkAnchors(bodyA, bodyB);
    expect(restLength).toBeCloseTo(28, 0);

    const rigid = linkConstraintOptions("rigid", bodyA, bodyB);
    const spring = linkConstraintOptions("spring", bodyA, bodyB);
    const rope = linkConstraintOptions("rope", bodyA, bodyB);

    expect(rigid.length).toBe(restLength);
    expect(spring.length).toBe(restLength);
    expect(rope.stiffness).toBeLessThan(0.1);
    expect(rigid.pointA?.x).toBeGreaterThan(0);
    expect(rigid.pointB?.x).toBeLessThan(0);
  });
});

describe("createLinkConstraints", () => {
  it("rigid uses two constraints, spring one", () => {
    const a = Matter.Bodies.circle(0, 0, 10);
    const b = Matter.Bodies.circle(0, 40, 10);
    expect(createLinkConstraints("rigid", a, b).length).toBe(2);
    expect(createLinkConstraints("spring", a, b).length).toBe(1);
    expect(createLinkConstraints("rope", a, b).length).toBe(1);
  });
});

describe("rebuildCompositeLinks", () => {
  it("refreshes lengths after bodies move", () => {
    const a = Matter.Bodies.circle(100, 100, 12);
    const b = Matter.Bodies.circle(100, 160, 12);
    const composite = Matter.Composite.create({ bodies: [a, b], constraints: [] });
    rebuildCompositeLinks(composite, [{ a: 0, b: 1, type: "rigid" }]);
    expect(composite.constraints.length).toBe(2);

    Matter.Body.setPosition(b, { x: 180, y: 100 });
    rebuildCompositeLinks(composite, [{ a: 0, b: 1, type: "rigid" }]);
    const span = constraintSpan(composite.constraints[0]!);
    expect(span).toBeCloseTo(linkAnchors(a, b).restLength, 0);
  });
});

describe("link types behave differently under force", () => {
  it("spring swings more than rigid on a chain", () => {
    const engineOpts = { gravity: GRAVITY, constraintIterations: 20 };

    function swing(type: "rigid" | "spring") {
      const engine = Matter.Engine.create(engineOpts);
      const group = Matter.Body.nextGroup(true);
      const top = Matter.Bodies.circle(400, 120, 10, {
        isStatic: true,
        collisionFilter: { group },
      });
      const mid = Matter.Bodies.circle(400, 190, 10, {
        collisionFilter: { group },
        frictionAir: 0.01,
      });
      const bot = Matter.Bodies.circle(400, 260, 10, {
        collisionFilter: { group },
        frictionAir: 0.01,
      });
      Matter.Composite.add(engine.world, [
        top,
        mid,
        bot,
        ...createLinkConstraints(type, top, mid),
        ...createLinkConstraints(type, mid, bot),
      ]);
      Matter.Body.applyForce(bot, bot.position, { x: 0.18, y: 0 });
      let maxSwing = 0;
      for (let i = 0; i < 120; i++) {
        updateMonsterRopeConstraints(engine.world);
        Matter.Engine.update(engine, 1000 / 60);
        maxSwing = Math.max(maxSwing, Math.abs(mid.position.x - 400));
      }
      return maxSwing;
    }

    expect(swing("spring")).toBeGreaterThan(swing("rigid") + 1.5);
  });

  it("rope allows more slack than rigid before tight pull", () => {
    const engine = Matter.Engine.create({ gravity: GRAVITY });
    const group = Matter.Body.nextGroup(true);
    const a = Matter.Bodies.circle(300, 200, 12, {
      isStatic: true,
      collisionFilter: { group },
    });
    const b = Matter.Bodies.circle(300, 260, 10, { collisionFilter: { group } });
    const [rope] = createLinkConstraints("rope", a, b);
    if (!rope) throw new Error("rope constraint missing");
    Matter.Composite.add(engine.world, [a, b, rope]);

    for (let i = 0; i < 30; i++) {
      updateMonsterRopeConstraints(engine.world);
      Matter.Engine.update(engine, 1000 / 60);
    }
    expect(rope.stiffness).toBeLessThan(0.01);
  });
});

describe("monster links under gravity", () => {
  it("starter presets stay connected after simulation", () => {
    for (const template of STARTER_MONSTERS) {
      const def = normalizeMonsterDef({
        ...template,
        id: "sim",
        createdAt: 0,
      });
      const built = buildMonster(def, 500, 250);
      expect(built).not.toBeNull();

      const engine = Matter.Engine.create({ gravity: GRAVITY });
      Matter.World.add(engine.world, built!.composite);

      for (let i = 0; i < 180; i++) {
        updateMonsterRopeConstraints(built!.composite);
        Matter.Engine.update(engine, 1000 / 60);
      }

      for (const link of def.links) {
        const a = built!.composite.bodies[link.a];
        const b = built!.composite.bodies[link.b];
        if (!(a && b)) continue;

        const dist = Matter.Vector.magnitude(
          Matter.Vector.sub(a.position, b.position),
        );
        const maxSpan = (a.circleRadius ?? 10) + (b.circleRadius ?? 10) + 120;
        expect(dist, `${template.name} ${link.type} ${link.a}-${link.b}`).toBeLessThan(
          maxSpan,
        );
      }
    }
  });
});
