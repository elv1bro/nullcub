import { describe, expect, it } from "vitest";
import { FACE_OVERLAY_EFFECTS } from "./faceEffects";

describe("faceEffects", () => {
  it("includes none and themed effects", () => {
    expect(FACE_OVERLAY_EFFECTS.map((e) => e.id)).toEqual([
      "none",
      "fire_eyes",
      "laser_eyes",
      "glitch",
      "halo",
      "demon",
    ]);
  });
});
