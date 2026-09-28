import { describe, expect, it } from "vitest";
import Matter, { Body } from "matter-js";
import { AI_PROFILES } from "@/battle/aiProfiles";
import { createStickman } from "@/utils/createStickman";
import { createBattleSession } from "./battleSession";
import { createArenaWalls } from "@/battle/headlessWalls";

function fighter(id: string, x: number, team: number, ai = false) {
  const composite = createStickman(x, 500, { render: { visible: false } });
  const head = composite.bodies.find((b) => b.label === "Head")!;
  for (const body of composite.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }
  return {
    id,
    composite,
    head,
    maxHp: 200,
    team,
    aiProfile: ai ? AI_PROFILES.normal : null,
  };
}

describe("team battle", () => {
  it("ends when one team remains in 2v2", () => {
    const arena = 1000;
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: arena, y: arena },
    ]);
    const walls = createArenaWalls(bounds, arena);
    const fighters = [
      fighter("a", 200, 0),
      fighter("b", 350, 0),
      fighter("c", 650, 1),
      fighter("d", 800, 1),
    ];
    const session = createBattleSession({
      arenaSize: arena,
      walls,
      fighters,
      compositesInWorld: false,
    });
    session.beginBattle();
    expect(session.isBattleOver()).toBe(false);

    // Убиваем команду 1
    for (const id of ["c", "d"]) {
      const f = session.getFighter(id)!;
      f.hp = 0;
    }
    expect(session.isBattleOver()).toBe(true);
    expect(session.resolveWinner()).toBe("a");
    session.destroy();
  });

  it("coop vs bots: humans share a team", () => {
    const arena = 1000;
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: arena, y: arena },
    ]);
    const walls = createArenaWalls(bounds, arena);
    const fighters = [
      fighter("p1", 250, 0),
      fighter("p2", 400, 0),
      fighter("bot1", 700, 1, true),
      fighter("bot2", 850, 1, true),
      fighter("bot3", 550, 1, true),
    ];
    const session = createBattleSession({
      arenaSize: arena,
      walls,
      fighters,
      compositesInWorld: false,
    });
    session.beginBattle();
    for (const id of ["bot1", "bot2", "bot3"]) {
      session.getFighter(id)!.hp = 0;
    }
    expect(session.isBattleOver()).toBe(true);
    expect(session.getFighter(session.resolveWinner()!)?.team).toBe(0);
    session.destroy();
  });
});
