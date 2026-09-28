import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { createBattleSession } from "@/core";
import { createArenaWalls } from "@/battle/headlessWalls";
import { MAX_HP } from "@/lib/combat";
import { createStickman } from "@/utils/createStickman";
import { stickmanCom } from "./stickmanIdleDamp";

describe("BattleSession idle symmetry", () => {
  it("player with zero input stays near spawn X for 30s", () => {
    const arena = 1000;
    const player = createStickman(360, 420, { render: { visible: false } });
    const opponent = createStickman(640, 420, { render: { visible: false } });
    const headP = player.bodies.find((b) => b.label === "Head")!;
    const headO = opponent.bodies.find((b) => b.label === "Head")!;
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: arena, y: arena },
    ]);

    const session = createBattleSession({
      arenaSize: arena,
      walls: createArenaWalls(bounds, arena),
      fighters: [
        {
          id: "player",
          composite: player,
          head: headP,
          maxHp: MAX_HP,
        },
        {
          id: "opponent",
          composite: opponent,
          head: headO,
          maxHp: MAX_HP,
        },
      ],
      playerCompositeId: player.id,
      opponentCompositeId: opponent.id,
      itemComposites: [],
    });
    session.beginBattle();
    const startX = stickmanCom(player).x;

    for (let i = 0; i < 30 * 60; i++) {
      session.tick(1000 / 60);
    }

    const endX = stickmanCom(player).x;
    expect(Math.abs(endX - startX)).toBeLessThan(35);
    expect(headP.position.y).toBeGreaterThan(420);
    session.destroy();
  });
});
