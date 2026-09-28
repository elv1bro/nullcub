import { describe, expect, it } from "vitest";
import { loadoutAllowsAbility } from "./loadoutGate";
import { emptyLoadout } from "./types";

describe("loadoutAllowsAbility", () => {
  it("allows all when loadout is missing", () => {
    expect(loadoutAllowsAbility(undefined, "dash")).toBe(true);
    expect(loadoutAllowsAbility(null, "flip")).toBe(true);
    expect(loadoutAllowsAbility(undefined, "brace")).toBe(true);
  });

  it("allows only base when slots empty", () => {
    const lo = emptyLoadout("flip");
    expect(loadoutAllowsAbility(lo, "flip")).toBe(true);
    expect(loadoutAllowsAbility(lo, "dash")).toBe(false);
    expect(loadoutAllowsAbility(lo, "brace")).toBe(false);
  });

  it("allows slotted abilities", () => {
    const lo = emptyLoadout("dash");
    lo.abilities = ["brace", null];
    expect(loadoutAllowsAbility(lo, "dash")).toBe(true);
    expect(loadoutAllowsAbility(lo, "brace")).toBe(true);
    expect(loadoutAllowsAbility(lo, "flip")).toBe(false);
  });
});
