import { describe, expect, it, beforeEach } from "vitest";
import { defaultLoadout } from "@/loadout";
import {
  advanceRoguelikeFloor,
  botsForFloor,
  claimHubCard,
  clearRoguelikeRun,
  enterPortal,
  failRoguelikeRun,
  getCurrentPortals,
  getRoguelikeRun,
  giveHubCard,
  resolveBattle,
  startRoguelikeRun,
  stealCard,
} from "./runState";

describe("roguelike runState", () => {
  beforeEach(() => clearRoguelikeRun());

  it("starts with prebuilt map, hub loot, and 4 corners", () => {
    const run = startRoguelikeRun(
      { you: defaultLoadout() },
      "easy",
      { playerIds: ["you"], playerNames: { you: "Hero" }, seed: 99 },
    );
    expect(run.phase).toBe("hub");
    expect(run.map.floors).toHaveLength(5);
    expect(run.players).toHaveLength(4);
    expect(run.players[0]?.corner).toBe("tl");
    expect(run.hubLoot.length).toBeGreaterThan(0);
    expect(getCurrentPortals().every((p) => p.face === "east")).toBe(true);
  });

  it("portal enter → battle → win reloads hub with portal loot", () => {
    startRoguelikeRun({ you: defaultLoadout() }, "normal", { seed: 1 });
    const portal = getCurrentPortals()[0]!;
    expect(enterPortal(portal.id)?.id).toBe(portal.id);
    expect(getRoguelikeRun()?.phase).toBe("battle");

    const after = resolveBattle(true);
    expect(after?.phase).toBe("hub");
    expect(after?.floor).toBe(2);
    expect(after?.hubEpoch).toBeGreaterThan(1);
    expect(after?.hubLoot).toEqual(portal.rewardPool);
  });

  it("loss ends the run", () => {
    startRoguelikeRun({ you: defaultLoadout() });
    enterPortal(getCurrentPortals()[0]!.id);
    resolveBattle(false);
    expect(getRoguelikeRun()?.failed).toBe(true);
    expect(getRoguelikeRun()?.phase).toBe("defeat");
  });

  it("claims hub loot into loadout", () => {
    startRoguelikeRun({ you: defaultLoadout() }, "normal", { seed: 3 });
    const card = getRoguelikeRun()!.hubLoot[0]!;
    expect(claimHubCard("you", card)).toBe(true);
    expect(getRoguelikeRun()!.hubLoot.includes(card)).toBe(false);
  });

  it("gives hub loot to another player and allows steal", () => {
    startRoguelikeRun(
      { you: defaultLoadout(), p2: defaultLoadout() },
      "normal",
      {
        playerIds: ["you", "p2"],
        playerNames: { you: "A", p2: "B" },
        seed: 11,
      },
    );
    const card = getRoguelikeRun()!.hubLoot.find((c) => c !== "dash" && c !== "flip" && c !== "brace")
      ?? getRoguelikeRun()!.hubLoot[0]!;
    expect(giveHubCard("p2", card)).toBe(true);
    expect(getRoguelikeRun()!.hubLoot.includes(card)).toBe(false);

    // украсть у p2 себе
    const stolen = stealCard("you", "p2", card);
    // база не крадётся — если карта была базой, steal false; иначе true
    if (card === "dash" || card === "flip" || card === "brace") {
      expect(stolen).toBe(false);
    } else {
      expect(stolen).toBe(true);
    }
  });

  it("hard fail ends the run", () => {
    startRoguelikeRun({ you: defaultLoadout() });
    failRoguelikeRun();
    expect(getRoguelikeRun()?.failed).toBe(true);
    expect(getRoguelikeRun()?.active).toBe(false);
  });

  it("scales bot count by difficulty", () => {
    expect(botsForFloor("easy", 1)).toBe(2);
    expect(botsForFloor("normal", 1)).toBe(3);
    expect(botsForFloor("hard", 1)).toBe(4);
    expect(botsForFloor("easy", 5)).toBeLessThanOrEqual(4);
  });

  it("advance helper still works", () => {
    startRoguelikeRun({ you: defaultLoadout() }, "easy");
    for (let i = 0; i < 4; i++) advanceRoguelikeFloor();
    const done = advanceRoguelikeFloor();
    expect(done?.active).toBe(false);
    expect(done?.floor).toBe(5);
  });
});
