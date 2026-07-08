import { describe, expect, it } from "vitest";
import {
  AVATAR_FACE_PRESETS,
  DEFAULT_AVATAR_FACE_ID,
  avatarFaceIdForSeed,
  getAvatarFacePreset,
  isValidAvatarFaceId,
} from "./avatarPresets";
import { generateAvatarRoster } from "./avatarRoster";

describe("avatarPresets", () => {
  it("has a campaign-sized roster (200-300 faces)", () => {
    expect(AVATAR_FACE_PRESETS.length).toBeGreaterThanOrEqual(250);
    expect(AVATAR_FACE_PRESETS.length).toBeLessThanOrEqual(340);
    expect(new Set(AVATAR_FACE_PRESETS.map((p) => p.id)).size).toBe(
      AVATAR_FACE_PRESETS.length,
    );
  });

  it("resolves unknown id to default", () => {
    expect(getAvatarFacePreset("nope").id).toBe(DEFAULT_AVATAR_FACE_ID);
    expect(isValidAvatarFaceId(DEFAULT_AVATAR_FACE_ID)).toBe(true);
    expect(isValidAvatarFaceId("nope")).toBe(false);
  });

  it("mixes species: animals, humans and monsters", () => {
    const kinds = new Set(AVATAR_FACE_PRESETS.map((p) => p.kind));
    expect(kinds.size).toBeGreaterThanOrEqual(10);
    expect(kinds.has("human")).toBe(true);
    expect(kinds.has("cat")).toBe(true);
    expect(kinds.has("robot")).toBe(true);
  });

  it("generates the roster deterministically (safe for net sync)", () => {
    const a = generateAvatarRoster();
    const b = generateAvatarRoster();
    expect(a.map((p) => p.id)).toEqual(b.map((p) => p.id));
    expect(a[0]).toEqual(b[0]);
  });

  it("picks a stable enemy face for a seed", () => {
    const id = avatarFaceIdForSeed("campaign-level-3");
    expect(avatarFaceIdForSeed("campaign-level-3")).toBe(id);
    expect(isValidAvatarFaceId(id)).toBe(true);
  });
});
