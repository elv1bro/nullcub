import { describe, expect, it } from "vitest";
import { buildItem } from "./buildItem";
import { computeDisarmChance, rollDisarm } from "./disarm";
import { items } from "./registry";
import "./index";

describe("items", () => {
  it("builds item with grip bodies", () => {
    const def = items.get("frying-pan");
    const composite = buildItem(def, 100, 200);
    expect(composite.bodies.length).toBe(2);
    expect(composite.constraints.length).toBeGreaterThan(0);
    const grip = composite.bodies.find((b) => b.label === "Grip");
    expect(grip).toBeDefined();
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
