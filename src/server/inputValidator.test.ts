import { describe, expect, it } from "vitest";
import { clampMove, InputRateLimiter } from "./inputValidator";

describe("clampMove", () => {
  it("returns empty input for null/undefined/non-object", () => {
    expect(clampMove(null).move).toEqual({ x: 0, y: 0 });
    expect(clampMove(undefined).move).toEqual({ x: 0, y: 0 });
    expect(clampMove("x").move).toEqual({ x: 0, y: 0 });
  });

  it("tolerates missing move", () => {
    const out = clampMove({ seq: 1, t: 2, dash: true });
    expect(out.move).toEqual({ x: 0, y: 0 });
    expect(out.dash).toBe(true);
    expect(out.flip).toBe(false);
  });

  it("clamps axes to ±1.05", () => {
    const out = clampMove({
      seq: 0,
      t: 0,
      move: { x: 99, y: -99 },
      grabL: false,
      grabR: false,
      dash: false,
      flip: false,
      freeze: false,
      reset: false,
    });
    expect(out.move.x).toBe(1.05);
    expect(out.move.y).toBe(-1.05);
  });
});

describe("InputRateLimiter", () => {
  it("rejects bursts over the per-second cap", () => {
    const lim = new InputRateLimiter();
    let accepted = 0;
    for (let i = 0; i < 100; i++) {
      if (lim.accept(1000 + i * 5)) accepted++;
    }
    expect(accepted).toBeLessThanOrEqual(45);
  });
});
