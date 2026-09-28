import { describe, expect, it } from "vitest";
import { computePlayerLevel, computePlayerXp } from "./playerLevel";
import { DEFAULT_PLAYER_STATS } from "./store";

describe("playerLevel", () => {
  it("starts as level 1 rookie with no progress grind", () => {
    const info = computePlayerLevel(DEFAULT_PLAYER_STATS);
    expect(info.level).toBe(1);
    expect(info.titleId).toBe("rookie");
    expect(info.xp).toBe(0);
    expect(info.progress).toBe(0);
  });

  it("gains XP from wins and medals", () => {
    const xp = computePlayerXp({
      ...DEFAULT_PLAYER_STATS,
      battles: 4,
      wins: 2,
      medals: { victory: 2, first_blood: 1 },
    });
    // 2*25 + 4*5 + 3*12 + 2*8 = 50+20+36+16 = 122
    expect(xp).toBe(122);
    const info = computePlayerLevel({
      ...DEFAULT_PLAYER_STATS,
      battles: 4,
      wins: 2,
      medals: { victory: 2, first_blood: 1 },
    });
    expect(info.level).toBeGreaterThan(1);
  });
});
