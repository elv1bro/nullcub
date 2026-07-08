import { describe, expect, it } from "vitest";
import { centerCrop, landmarksToCrop, smoothCrop } from "./faceCrop";

describe("landmarksToCrop", () => {
  it("builds square crop around face bbox", () => {
    const crop = landmarksToCrop(
      [
        { x: 0.4, y: 0.3 },
        { x: 0.6, y: 0.5 },
      ],
      640,
      480,
      1.5,
    );
    expect(crop).not.toBeNull();
    expect(crop!.sw).toBeCloseTo(crop!.sh, 1);
    expect(crop!.sw).toBeGreaterThan(80);
  });

  it("returns null for empty landmarks", () => {
    expect(landmarksToCrop([], 640, 480)).toBeNull();
  });
});

describe("smoothCrop", () => {
  it("interpolates toward new crop", () => {
    const a = { sx: 0, sy: 0, sw: 100, sh: 100 };
    const b = { sx: 100, sy: 100, sw: 200, sh: 200 };
    const mid = smoothCrop(a, b);
    expect(mid.sx).toBeGreaterThan(0);
    expect(mid.sx).toBeLessThan(100);
  });
});

describe("centerCrop", () => {
  it("fits in frame", () => {
    const c = centerCrop(640, 480);
    expect(c.sw).toBe(480);
    expect(c.sx).toBe(80);
  });
});
