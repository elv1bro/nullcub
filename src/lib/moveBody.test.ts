import { describe, expect, it } from "vitest";
import { toMoveInput } from "./moveBody";

describe("toMoveInput", () => {
  it("inverts world direction for moveBody (same as keyboard W = up)", () => {
    const left = toMoveInput({ x: -1, y: 0 });
    expect(left.x).toBe(1);
    expect(left.y).toBeCloseTo(0);

    const up = toMoveInput({ x: 0, y: -1 });
    expect(up.x).toBeCloseTo(0);
    expect(up.y).toBe(1);
  });
});
