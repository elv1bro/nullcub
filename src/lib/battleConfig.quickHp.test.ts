import { describe, expect, it } from "vitest";
import {
  clampQuickOpponentHp,
  getBattleConfig,
  QUICK_OPPONENT_HP_DEFAULT,
  setBattleQuick,
} from "./battleConfig";

describe("quick opponent HP", () => {
  it("presets clamp to nearest option", () => {
    expect(clampQuickOpponentHp(1)).toBe(1);
    expect(clampQuickOpponentHp(1000)).toBe(1000);
    expect(clampQuickOpponentHp(10000)).toBe(10000);
    expect(clampQuickOpponentHp(900)).toBe(1000);
    expect(clampQuickOpponentHp(80)).toBe(100);
  });

  it("setBattleQuick stores opponentHp", () => {
    setBattleQuick({ opponentHp: 5000 });
    const cfg = getBattleConfig();
    expect(cfg).toEqual({ kind: "quick", opponentHp: 5000 });
    setBattleQuick();
    expect(getBattleConfig()).toEqual({
      kind: "quick",
      opponentHp: QUICK_OPPONENT_HP_DEFAULT,
    });
  });
});
