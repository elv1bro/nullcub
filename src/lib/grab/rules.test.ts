import { describe, expect, it } from "vitest";
import { computeDamage } from "@/lib/combat";
import Matter from "matter-js";
import { createFighterGrabState } from "./types";
import {
  createGrabHitTracker,
  filterGrabDamage,
  GRAB_ATTACK_DAMAGE_MULT,
  GRAB_HOLDER_INCOMING_DAMAGE_MULT,
  recordGrabVictimHit,
  shouldForceReleaseGrabber,
} from "./rules";

describe("grab damage rules", () => {
  it("reduces grabber damage to held victim", () => {
    const playerGrab = createFighterGrabState("player");
    playerGrab.left = {
      ...playerGrab.left,
      phase: "attached",
      target: { bodyId: 1, compositeId: 99, kind: "fighter" },
    };

    const bodyA = Matter.Bodies.circle(0, 0, 10);
    const bodyB = Matter.Bodies.circle(20, 0, 10);
    Matter.Body.setVelocity(bodyA, { x: 5, y: 0 });
    Matter.Body.setVelocity(bodyB, { x: -1, y: 0 });

    const raw = computeDamage(bodyA, bodyB);
    expect(raw.victim).not.toBe("none");

    const filtered = filterGrabDamage(1, 99, raw, {
      playerCompositeId: 1,
      opponentCompositeId: 99,
      playerGrab,
      opponentGrab: null,
    });

    expect(filtered.damageB).toBeCloseTo(raw.damageB * GRAB_ATTACK_DAMAGE_MULT);
    expect(filtered.damageB).toBeGreaterThan(0);
  });

  it("reduces (not zeroes) victim damage to the holder", () => {
    const playerGrab = createFighterGrabState("player");
    playerGrab.left = {
      ...playerGrab.left,
      phase: "attached",
      target: { bodyId: 2, compositeId: 99, kind: "fighter" },
    };

    const raw = {
      damageA: 10,
      damageB: 10,
      victim: "both" as const,
      impactSpeed: 12,
      closing: 12,
    };

    const filtered = filterGrabDamage(1, 99, raw, {
      playerCompositeId: 1,
      opponentCompositeId: 99,
      playerGrab,
      opponentGrab: null,
    });

    // Держатель A: урон приглушён, но не 0 — вырываться ударами можно.
    expect(filtered.damageA).toBeCloseTo(10 * GRAB_HOLDER_INCOMING_DAMAGE_MULT);
    expect(filtered.damageA).toBeGreaterThan(0);
    expect(filtered.damageB).toBeCloseTo(10 * GRAB_ATTACK_DAMAGE_MULT);
    expect(filtered.damageB).toBeGreaterThan(0);
  });

  it("2 hits in 1s triggers forced release sides", () => {
    const tracker = createGrabHitTracker();
    expect(recordGrabVictimHit(tracker, 0)).toBe(false);
    expect(recordGrabVictimHit(tracker, 400)).toBe(true);
  });

  it("shouldForceReleaseGrabber finds attached hands", () => {
    const grab = createFighterGrabState("p");
    grab.right = {
      ...grab.right,
      phase: "attached",
      target: { bodyId: 5, compositeId: 42, kind: "fighter" },
    };
    expect(shouldForceReleaseGrabber(grab, 42)).toEqual(["right"]);
  });
});
