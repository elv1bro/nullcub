import { describe, expect, it } from "vitest";
import { getAvatarFacePreset } from "./avatarPresets";
import { bodyColorsFromAvatar } from "./bodyColorsFromAvatar";
import { parseHex } from "./color";

function luminance(hex: string): number {
  const [r, g, b] = parseHex(hex);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

describe("bodyColorsFromAvatar", () => {
  it("returns darker secondary than main", () => {
    for (const id of ["cat", "robot", "oni", "ninja", "ghost", "kai"]) {
      const preset = getAvatarFacePreset(id);
      const { main, secondary } = bodyColorsFromAvatar(preset);
      expect(luminance(secondary)).toBeLessThan(luminance(main) + 0.05);
    }
  });

  it("robot uses neon accent on body", () => {
    const { main } = bodyColorsFromAvatar(getAvatarFacePreset("robot"));
    expect(main.toLowerCase()).toBe("#3ad6ff");
  });
});
