import { describe, expect, it } from "vitest";
import { mergeCampaignOrder, mergePlayerStats } from "./mergeProgress";

describe("mergeProgress", () => {
  it("keeps the higher campaign unlock", () => {
    expect(mergeCampaignOrder(1, 3)).toBe(3);
    expect(mergeCampaignOrder(4, 2)).toBe(4);
  });

  it("merges stats with max counters", () => {
    const merged = mergePlayerStats(
      {
        battles: 2,
        wins: 1,
        losses: 1,
        lossStreak: 1,
        medals: { first_blood: 1, victory: 1 },
      },
      {
        battles: 5,
        wins: 4,
        losses: 0,
        lossStreak: 0,
        medals: { first_blood: 2, knockout: 1 },
      },
    );
    expect(merged.battles).toBe(5);
    expect(merged.wins).toBe(4);
    expect(merged.losses).toBe(1);
    expect(merged.medals.first_blood).toBe(2);
    expect(merged.medals.victory).toBe(1);
    expect(merged.medals.knockout).toBe(1);
  });
});
