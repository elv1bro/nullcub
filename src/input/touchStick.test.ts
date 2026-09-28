import { describe, expect, it } from "vitest";

/** Та же математика, что в VirtualBattleStick — без DOM. */
function clampStick(
  dx: number,
  dy: number,
  radius = 54,
  deadzone = 0.18,
): { x: number; y: number } {
  const len = Math.hypot(dx, dy);
  const nx = len > radius ? (dx / len) * radius : dx;
  const ny = len > radius ? (dy / len) * radius : dy;
  let x = -nx / radius;
  let y = -ny / radius;
  if (Math.abs(x) < deadzone) x = 0;
  if (Math.abs(y) < deadzone) y = 0;
  const mag = Math.hypot(x, y);
  if (mag > 1) {
    x /= mag;
    y /= mag;
  }
  return { x, y };
}

describe("touch stick → game vector", () => {
  it("finger left → +x (game left)", () => {
    const v = clampStick(-54, 0);
    expect(v.x).toBeGreaterThan(0.9);
    expect(v.y).toBe(0);
  });

  it("finger up → +y (game up)", () => {
    const v = clampStick(0, -54);
    expect(v.y).toBeGreaterThan(0.9);
    expect(v.x).toBe(0);
  });

  it("deadzone zeros tiny nudges", () => {
    const v = clampStick(4, 3);
    expect(v.x).toBe(0);
    expect(v.y).toBe(0);
  });
});
