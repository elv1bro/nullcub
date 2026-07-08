import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import {
  ATTACKER_RECOIL,
  computeDamage,
  DAMAGE_PER_SPEED,
  MIN_IMPACT_SPEED,
} from "./combat";
import { SPIKE_ATK_MULT } from "@/items/resolveWeaponHit";

function body(
  label: string,
  x: number,
  y: number,
  vx = 0,
  vy = 0,
): Matter.Body {
  const b = Matter.Bodies.circle(x, y, 10, { label });
  Matter.Body.setVelocity(b, { x: vx, y: vy });
  return b;
}

describe("computeDamage", () => {
  it("returns zero for gentle contact / sliding", () => {
    const a = body("Upper Right Arm", 0, 0, 0, 8);
    const b = body("Chest", 20, 0, 0, 7);
    expect(computeDamage(a, b).damageB).toBe(0);
  });

  it("returns zero below impact threshold", () => {
    const a = body("Upper Right Arm", 0, 0, MIN_IMPACT_SPEED * 0.5, 0);
    const b = body("Head", 25, 0);
    expect(computeDamage(a, b).damageB).toBe(0);
  });

  it("when A strikes B head, B takes main damage", () => {
    const hand = body("Upper Right Arm", 0, 0, 10, 0);
    const head = body("Head", 25, 0, 0, 0);
    const result = computeDamage(hand, head);

    expect(result.victim).toBe("b");
    expect(result.damageB).toBeGreaterThan(40);
    expect(result.damageB).toBeGreaterThan(result.damageA);
    expect(result.damageA).toBeCloseTo(result.damageB * ATTACKER_RECOIL, 4);
  });

  it("victim is the same when pair order is swapped", () => {
    const hand = body("Upper Right Arm", 0, 0, 10, 0);
    const head = body("Head", 25, 0, 0, 0);
    const forward = computeDamage(hand, head);
    const swapped = computeDamage(head, hand);

    expect(forward.damageB).toBeGreaterThan(40);
    expect(swapped.damageA).toBeCloseTo(forward.damageB, 0);
  });

  it("head hit hurts more than arm hit at same impact", () => {
    const fist = body("Upper Right Arm", 0, 0, 12, 0);
    const headHit = computeDamage(fist, body("Head", 20, 0)).damageB;
    const armHit = computeDamage(fist, body("Upper Left Arm", 20, 0)).damageB;
    expect(headHit).toBeGreaterThan(armHit);
  });

  it("scales with impact speed", () => {
    const slow = computeDamage(
      body("Chest", 0, 0, 4, 0),
      body("Chest", 20, 0),
    ).damageB;
    const fast = computeDamage(
      body("Chest", 0, 0, 12, 0),
      body("Chest", 20, 0),
    ).damageB;
    expect(fast).toBeGreaterThan(slow * 2);
    expect(fast).toBeCloseTo(12 * DAMAGE_PER_SPEED, 0);
  });

  it("safe limb as victim takes no damage", () => {
    const fist = body("Upper Right Arm", 0, 0, 12, 0);
    const tip = body("Lower Right Arm", 20, 0);
    expect(computeDamage(fist, tip).damageB).toBe(0);
  });

  it("armor parts take no HP damage", () => {
    const fist = body("Upper Right Arm", 0, 0, 12, 0);
    const plate = body("Armor", 20, 0);
    expect(computeDamage(fist, plate).damageB).toBe(0);
  });

  it("spike part deals pierce damage multiplied by SPIKE_ATK_MULT", () => {
    const fist = body("Upper Right Arm", 0, 0, 10, 0);
    const spike = body("Spike", 0, 0, 10, 0);
    const bare = computeDamage(fist, body("Chest", 25, 0));
    const spiked = computeDamage(spike, body("Chest", 25, 0));

    expect(spiked.damageB).toBeCloseTo(bare.damageB * SPIKE_ATK_MULT, 4);
    expect(spiked.damageTypeId).toBe("pierce");
  });
});
