import { describe, expect, it } from "vitest";
import { sanitizeHostBattleState } from "./sanitizeBattleState";

describe("sanitizeHostBattleState", () => {
  it("clamps HP into [0, max]", () => {
    const out = sanitizeHostBattleState({
      playerHp: 5000,
      opponentHp: -20,
      battleOver: false,
      winner: null,
      playerName: "A",
      opponentName: "B",
    });
    expect(out.playerHp).toBe(1000);
    expect(out.opponentHp).toBe(0);
    expect(out.battleOver).toBe(false);
  });

  it("rejects NaN HP", () => {
    const out = sanitizeHostBattleState({
      playerHp: Number.NaN,
      opponentHp: Number.POSITIVE_INFINITY,
      battleOver: false,
      winner: null,
      playerName: "A",
      opponentName: "B",
    });
    expect(out.playerHp).toBe(1000);
    expect(out.opponentHp).toBe(1000);
  });

  it("does not end battle when both alive and winner missing", () => {
    const out = sanitizeHostBattleState({
      playerHp: 800,
      opponentHp: 700,
      battleOver: true,
      winner: null,
      playerName: "A",
      opponentName: "B",
    });
    expect(out.battleOver).toBe(false);
    expect(out.winner).toBeNull();
  });

  it("keeps explicit winner when battleOver", () => {
    const out = sanitizeHostBattleState({
      playerHp: 0,
      opponentHp: 400,
      battleOver: true,
      winner: "opponent",
      playerName: "A",
      opponentName: "B",
    });
    expect(out.battleOver).toBe(true);
    expect(out.winner).toBe("opponent");
  });
});
