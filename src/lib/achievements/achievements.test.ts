import { describe, expect, it } from "vitest";
import {
  createBattleTracker,
  recordBattleHit,
  recordPlayerKnockoutWin,
} from "./battleTracker";
import { evaluateBattleMedals } from "./evaluate";
import { HEAVY_DAMAGE } from "@/lib/hitEffects/store";

describe("battle achievements", () => {
  it("awards first blood and combo medals", () => {
    const tracker = createBattleTracker();
    recordBattleHit(tracker, "player", 10, 1000);
    recordBattleHit(tracker, "player", 12, 1200);
    recordBattleHit(tracker, "player", 8, 1500);

    const medals = evaluateBattleMedals(tracker, "player", 500);
    expect(medals).toContain("first_blood");
    expect(medals).toContain("combo_3");
    expect(medals).toContain("victory");
  });

  it("awards heavy and brutal hits", () => {
    const tracker = createBattleTracker();
    recordBattleHit(tracker, "player", HEAVY_DAMAGE, 1000);
    recordBattleHit(tracker, "player", 55, 1300);

    const medals = evaluateBattleMedals(tracker, "player", 800);
    expect(medals).toContain("heavy_hit");
    expect(medals).toContain("brutal_hit");
  });

  it("awards knockout and clutch on low-hp win", () => {
    const tracker = createBattleTracker();
    recordPlayerKnockoutWin(tracker);

    const medals = evaluateBattleMedals(tracker, "player", 200);
    expect(medals).toContain("knockout");
    expect(medals).toContain("clutch");
  });

  it("skips victory medals on defeat", () => {
    const tracker = createBattleTracker();
    recordBattleHit(tracker, "player", HEAVY_DAMAGE, 1000);

    const medals = evaluateBattleMedals(tracker, "opponent", 0);
    expect(medals).not.toContain("victory");
    expect(medals).toContain("heavy_hit");
  });

  it("awards revenge, flawless, bouncer, and workshop", () => {
    const tracker = createBattleTracker();
    recordBattleHit(tracker, "player", 20, 1000);

    const revenge = evaluateBattleMedals(tracker, "player", 500, 1000, {
      lossStreakBeforeBattle: 2,
      battleConfig: { kind: "quick" },
    });
    expect(revenge).toContain("revenge");

    const flawless = evaluateBattleMedals(tracker, "player", 500);
    expect(flawless).toContain("flawless");

    const bouncer = evaluateBattleMedals(tracker, "player", 500, 1000, {
      battleConfig: { kind: "campaign", chapterId: "bard" },
    });
    expect(bouncer).toContain("bouncer");

    const workshop = evaluateBattleMedals(tracker, "player", 500, 1000, {
      battleConfig: { kind: "monster", monsterId: "test" },
    });
    expect(workshop).toContain("workshop");
  });

  it("does not award flawless when player took damage", () => {
    const tracker = createBattleTracker();
    recordBattleHit(tracker, "opponent", 10, 1000);
    recordBattleHit(tracker, "player", 20, 1100);

    const medals = evaluateBattleMedals(tracker, "player", 500);
    expect(medals).not.toContain("flawless");
  });
});
