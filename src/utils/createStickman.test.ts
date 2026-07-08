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

function restLength(a: Matter.Body, b: Matter.Body): number {
  return Matter.Vector.magnitude(
    Matter.Vector.sub(a.position, b.position),
  );
}

function bottomChestBody(composite: Matter.Composite): Matter.Body {
  const chests = composite.bodies.filter((b) => b.label === "Chest");
  return chests.reduce((a, b) => (a.position.y > b.position.y ? a : b));
}

describe("createStickman leg symmetry", () => {
  it("hips use the same constraint count and stiffness as left", () => {
    const stickman = createStickman(400, 500);
    const chest = bottomChestBody(stickman);
    const upperLeft = stickman.bodies.filter((b) => b.label === "Upper Left Leg");
    const upperRight = stickman.bodies.filter((b) => b.label === "Upper Right Leg");

    const leftHip = upperLeft.at(-1)!;
    const rightHip = upperRight.at(0)!;

    const leftLinks = constraintsBetween(stickman, chest, leftHip);
    const rightLinks = constraintsBetween(stickman, chest, rightHip);

    expect(leftLinks).toHaveLength(2);
    expect(rightLinks).toHaveLength(2);
    expect(leftLinks.map((c) => c.stiffness).sort()).toEqual(
      rightLinks.map((c) => c.stiffness).sort(),
    );
  });

  it("knee joints sit at the same span as on the left leg", () => {
    const stickman = createStickman(400, 500);
    const upperLeft = stickman.bodies.filter((b) => b.label === "Upper Left Leg");
    const lowerLeft = stickman.bodies.filter((b) => b.label === "Lower Left Leg");
    const upperRight = stickman.bodies.filter((b) => b.label === "Upper Right Leg");
    const lowerRight = stickman.bodies.filter((b) => b.label === "Lower Right Leg");

    const leftKneeUpper = upperLeft.at(0)!;
    const leftKneeLower = lowerLeft.at(-1)!;
    const rightKneeUpper = upperRight.at(-1)!;
    const rightKneeLower = lowerRight.at(0)!;

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

    expect(leftKneeLinks).toHaveLength(3);
    expect(rightKneeLinks).toHaveLength(3);
    expect(leftKneeLinks.map((c) => c.stiffness).sort()).toEqual(
      rightKneeLinks.map((c) => c.stiffness).sort(),
    );
  });
});
