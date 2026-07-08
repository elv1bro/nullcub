import Matter, { Composite, Engine } from "matter-js";
import { describe, expect, it } from "vitest";
import { releaseRagdollConstraints } from "./victoryKoScatter";

function miniRagdoll(): Composite {
  const a = Matter.Bodies.rectangle(0, 0, 10, 10);
  const b = Matter.Bodies.rectangle(40, 0, 10, 10);
  const link = Matter.Constraint.create({
    bodyA: a,
    bodyB: b,
    length: 30,
    stiffness: 1,
  });
  return Composite.create({ bodies: [a, b], constraints: [link] });
}

describe("releaseRagdollConstraints", () => {
  it("removes constraints from nested stickman composite in world", () => {
    const engine = Engine.create();
    const ragdoll = miniRagdoll();
    Composite.add(engine.world, ragdoll);

    expect(Composite.allConstraints(engine.world).length).toBe(1);

    releaseRagdollConstraints(engine, ragdoll);

    expect(ragdoll.constraints.length).toBe(0);
    expect(Composite.allConstraints(engine.world).length).toBe(0);
  });
});
