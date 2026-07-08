import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { computeDamage, DAMAGE_PER_SPEED } from "./combat";
import {
  computeKnockback,
  KNOCKBACK_ATTACKER_SCALE,
  previewStrike,
} from "./knockback";

function body(label: string, x: number, y: number, vx = 0): Matter.Body {
  const b = Matter.Bodies.circle(x, y, 10, { label, mass: 1 });
  Matter.Body.setVelocity(b, { x: vx, y: 0 });
  return b;
}

describe("computeKnockback", () => {
  it("returns zero impulse when there is no victim", () => {
    const a = body("Upper Right Arm", 0, 0, 0.5);
    const b = body("Head", 30, 0);
    const damage = computeDamage(a, b);
    const kb = computeKnockback(damage, a, b);
    expect(kb.victimMagnitude).toBe(0);
  });

  it("pushes victim harder than attacker recoil", () => {
    const a = body("Upper Right Arm", 0, 0, 10);
    const b = body("Head", 30, 0);
    const damage = computeDamage(a, b);
    const kb = computeKnockback(damage, a, b);

    expect(damage.victim).toBe("b");
    expect(kb.victimMagnitude).toBeGreaterThan(0);
    expect(Matter.Vector.magnitude(kb.impulseB)).toBeGreaterThan(
      Matter.Vector.magnitude(kb.impulseA),
    );
  });

  it("scales knockback with impact speed and damage", () => {
    const slow = previewStrike(body("Chest", 0, 0, 4), body("Chest", 30, 0), 4);
    const fast = previewStrike(body("Chest", 0, 0, 12), body("Head", 30, 0), 12);
    expect(fast.knockback.victimMagnitude).toBeGreaterThan(slow.knockback.victimMagnitude);
    expect(fast.damage.damageB).toBeCloseTo(12 * DAMAGE_PER_SPEED * 1.6, 0);
  });

  it("attacker recoil uses configured scale", () => {
    const a = body("Upper Right Arm", 0, 0, 10);
    const b = body("Chest", 30, 0);
    const damage = computeDamage(a, b);
    const kb = computeKnockback(damage, a, b);
    const victimMag = Matter.Vector.magnitude(kb.impulseB);
    const attackerMag = Matter.Vector.magnitude(kb.impulseA);
    expect(attackerMag).toBeCloseTo(victimMag * KNOCKBACK_ATTACKER_SCALE, 1);
  });
});
