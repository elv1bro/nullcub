import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { createStickman } from "./createStickman";

function constraintsBetween(
  composite: Matter.Composite,
  a: Matter.Body,
  b: Matter.Body,
): Matter.Constraint[] {
  return composite.constraints.filter(
    (c) =>
      (c.bodyA === a && c.bodyB === b) || (c.bodyA === b && c.bodyB === a),
  );
}

function segments(composite: Matter.Composite, label: string): Matter.Body[] {
  return composite.bodies.filter((b) => b.label === label);
}

function restLength(a: Matter.Body, b: Matter.Body): number {
  return Matter.Vector.magnitude(
    Matter.Vector.sub(a.position, b.position),
  );
}

function bottomChestBody(composite: Matter.Composite): Matter.Body {
  const chests = composite.bodies.filter((b) => b.label === "Chest");
  return chests.reduce((a, b) => (a.position.y > b.position.y ? a : b));
}

// Ноги — вертикальные цепочки сверху вниз, поэтому у обеих ног
// индекс 0 это бедро, а последний сегмент — колено/ступня.
describe("createStickman leg symmetry", () => {
  it("hips use the same constraint count and stiffness on both legs", () => {
    const stickman = createStickman(400, 500);
    const chest = bottomChestBody(stickman);

    const leftHip = segments(stickman, "Upper Left Leg").at(0)!;
    const rightHip = segments(stickman, "Upper Right Leg").at(0)!;

    const leftLinks = constraintsBetween(stickman, chest, leftHip);
    const rightLinks = constraintsBetween(stickman, chest, rightHip);

    expect(leftLinks).toHaveLength(2);
    expect(rightLinks).toHaveLength(2);
    expect(leftLinks.map((c) => c.stiffness).sort()).toEqual(
      rightLinks.map((c) => c.stiffness).sort(),
    );
  });

  it("knee joints sit at the same span on both legs", () => {
    const stickman = createStickman(400, 500);

    const leftKneeUpper = segments(stickman, "Upper Left Leg").at(-1)!;
    const leftKneeLower = segments(stickman, "Lower Left Leg").at(0)!;
    const rightKneeUpper = segments(stickman, "Upper Right Leg").at(-1)!;
    const rightKneeLower = segments(stickman, "Lower Right Leg").at(0)!;

    const leftSpan = restLength(leftKneeUpper, leftKneeLower);
    const rightSpan = restLength(rightKneeUpper, rightKneeLower);

    expect(leftSpan).toBeCloseTo(rightSpan, 0);
    expect(leftSpan).toBeLessThan(30);

    const leftKneeLinks = constraintsBetween(
      stickman,
      leftKneeUpper,
      leftKneeLower,
    );
    const rightKneeLinks = constraintsBetween(
      stickman,
      rightKneeUpper,
      rightKneeLower,
    );

    expect(leftKneeLinks).toHaveLength(2);
    expect(rightKneeLinks).toHaveLength(2);
    expect(leftKneeLinks.map((c) => c.stiffness).sort()).toEqual(
      rightKneeLinks.map((c) => c.stiffness).sort(),
    );
  });

  it("legs hang below the hip on opposite sides of the spawn line", () => {
    const spawnX = 400;
    const stickman = createStickman(spawnX, 500);
    const hip = bottomChestBody(stickman);

    const left = segments(stickman, "Lower Left Leg").at(-1)!;
    const right = segments(stickman, "Lower Right Leg").at(-1)!;

    expect(left.position.y).toBeGreaterThan(hip.position.y);
    expect(right.position.y).toBeGreaterThan(hip.position.y);
    expect(left.position.x).toBeLessThan(spawnX);
    expect(right.position.x).toBeGreaterThan(spawnX);
    expect(spawnX - left.position.x).toBeCloseTo(right.position.x - spawnX, 0);
  });
});
