import { describe, expect, it } from "vitest";
import { buildItem, weaponMassOf } from "./buildItem";
import { computeDisarmChance, rollDisarm } from "./disarm";
import { items } from "./registry";
import { findGripBody } from "./weaponHold";
import "./index";

describe("items", () => {
  it("builds solid frying-pan with grip and mass", () => {
    const def = items.get("frying-pan");
    const composite = buildItem(def, 100, 200);
    expect(composite.bodies.length).toBe(1);
    expect(findGripBody(composite)).toBeDefined();
    expect(weaponMassOf(composite)).toBeGreaterThan(1);
    expect(def.solid).toBeTruthy();
  });

  it("builds rope flail with constraints", () => {
    const def = items.get("chain-flail");
    const composite = buildItem(def, 100, 200);
    expect(composite.bodies.length).toBeGreaterThanOrEqual(2);
    expect(composite.constraints.length).toBeGreaterThan(0);
    expect(findGripBody(composite)).toBeDefined();
  });

  it("disarm chance scales with item and toughness", () => {
    const def = items.get("chain-flail");
    expect(computeDisarmChance(def, 0)).toBeCloseTo(0.0143, 3);
    expect(computeDisarmChance(def, 1)).toBeLessThan(0.015);
  });

  it("rollDisarm respects rng", () => {
    expect(rollDisarm(1, () => 0)).toBe(true);
    expect(rollDisarm(0, () => 0.5)).toBe(false);
  });
});
