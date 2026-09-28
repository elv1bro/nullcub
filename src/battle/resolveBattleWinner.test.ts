import { describe, expect, it } from "vitest";
import { resolveBattleWinner, type FighterRuntime } from "./types";

function stub(id: string, team: number, hp: number): FighterRuntime {
  return {
    id,
    team,
    hp,
    maxHp: 100,
    name: id,
    colors: { main: "#fff", secondary: "#000" },
    controller: "ai",
    face: "synthetic",
    isLocalHuman: false,
    composite: { id: 0 } as FighterRuntime["composite"],
    head: {} as FighterRuntime["head"],
  };
}

describe("resolveBattleWinner", () => {
  it("coop ends when one team remains", () => {
    const fighters = [
      stub("p1", 0, 50),
      stub("p2", 0, 10),
      stub("bot", 1, 0),
    ];
    expect(resolveBattleWinner("coop", fighters)).toBe("p1");
  });

  it("coop not over while both teams alive", () => {
    const fighters = [
      stub("p1", 0, 50),
      stub("bot", 1, 20),
    ];
    expect(resolveBattleWinner("coop", fighters)).toBeNull();
  });
});
