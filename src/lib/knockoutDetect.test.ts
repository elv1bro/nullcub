import { describe, expect, it } from "vitest";
import { isKnockoutFromLethalHit } from "./knockoutDetect";

describe("isKnockoutFromLethalHit", () => {
  it("detects lethal hit after hp already applied", () => {
    expect(isKnockoutFromLethalHit(0, 25)).toBe(true);
    expect(isKnockoutFromLethalHit(0, 0)).toBe(false);
  });

  it("ignores hits while fighter still alive", () => {
    expect(isKnockoutFromLethalHit(40, 10)).toBe(false);
  });

  it("ignores zero hp without damage this hit", () => {
    expect(isKnockoutFromLethalHit(0, 0)).toBe(false);
  });
});
