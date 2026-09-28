import { describe, expect, it } from "vitest";
import Matter from "matter-js";
import {
  applyLoadoutCastEffect,
  resolveLoadoutCast,
} from "./castAbility";

describe("castAbility", () => {
  it("maps base abilities to wired flags", () => {
    expect(resolveLoadoutCast("dash")).toEqual({
      ok: true,
      kind: "base",
      base: "dash",
    });
    expect(resolveLoadoutCast("flip").ok).toBe(true);
  });

  it("treats stub actives as castable effects", () => {
    const r = resolveLoadoutCast("slam");
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.kind).toBe("effect");
  });

  it("applies a visible impulse for offense cast", () => {
    const head = Matter.Bodies.circle(100, 100, 20);
    Matter.Body.setVelocity(head, { x: 0, y: 0 });
    applyLoadoutCastEffect(head, "slam", Matter.Vector.create(1, 0));
    expect(Math.abs(head.force.x) + Math.abs(head.force.y)).toBeGreaterThan(0);
  });
});
