import { describe, expect, it } from "vitest";
import {
  colorsForSide,
  formatHeartCount,
  formatHeartDamage,
} from "./fighterColors";

describe("fighterColors", () => {
  it("formats heart damage", () => {
    expect(formatHeartDamage(20.4)).toBe("-20 ♥");
    expect(formatHeartDamage(0.2)).toBe("-1 ♥");
  });

  it("formats heart count", () => {
    expect(formatHeartCount(847.2)).toBe("848 ♥");
  });

  it("returns colors per side", () => {
    expect(colorsForSide("player").main).toBe("#38bdf8");
    expect(colorsForSide("opponent").main).toBe("#f87171");
  });
});
