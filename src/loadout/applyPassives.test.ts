import { describe, expect, it } from "vitest";
import { computeLoadoutCombatMods } from "./applyPassives";
import { emptyLoadout } from "./types";

describe("computeLoadoutCombatMods", () => {
  it("returns identity mods for empty items", () => {
    const mods = computeLoadoutCombatMods(emptyLoadout());
    expect(mods.atkMult).toBe(1);
    expect(mods.defPct).toBe(0);
    expect(mods.moveMult).toBe(1);
    expect(mods.knockbackOutMult).toBe(1);
    expect(mods.critChance).toBe(0);
    expect(mods.headDefBonus).toBe(0);
  });

  it("stacks gloves + armor + boots", () => {
    const loadout = emptyLoadout();
    loadout.items = ["gloves", "armor"];
    const mods = computeLoadoutCombatMods(loadout);
    expect(mods.atkMult).toBeCloseTo(1.12, 5);
    expect(mods.defPct).toBeCloseTo(15, 5);
  });

  it("applies helm head bonus and horseshoe knockback", () => {
    const loadout = emptyLoadout();
    loadout.items = ["helm", "horseshoe"];
    const mods = computeLoadoutCombatMods(loadout);
    expect(mods.headDefBonus).toBeCloseTo(0.15, 5);
    expect(mods.knockbackOutMult).toBeCloseTo(1.18, 5);
    expect(mods.defPct).toBeCloseTo(5, 5);
  });

  it("adds amulet crit and multiplies atk", () => {
    const loadout = emptyLoadout();
    loadout.items = ["amulet", "gloves"];
    const mods = computeLoadoutCombatMods(loadout);
    expect(mods.critChance).toBeCloseTo(0.08, 5);
    expect(mods.atkMult).toBeCloseTo(1.04 * 1.12, 5);
  });

  it("applies boots move mult", () => {
    const loadout = emptyLoadout();
    loadout.items = ["boots", null];
    const mods = computeLoadoutCombatMods(loadout);
    expect(mods.moveMult).toBeCloseTo(1.12, 5);
  });

  it("stacks extra items beyond loadout slots", () => {
    const loadout = emptyLoadout();
    loadout.items = ["gloves", "armor"];
    const mods = computeLoadoutCombatMods(loadout, ["boots", "amulet"]);
    expect(mods.atkMult).toBeCloseTo(1.12 * 1.04, 5);
    expect(mods.defPct).toBeCloseTo(15, 5);
    expect(mods.moveMult).toBeCloseTo(1.12, 5);
    expect(mods.critChance).toBeCloseTo(0.08, 5);
  });
});
