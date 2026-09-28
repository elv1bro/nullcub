import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { createArenaWalls } from "@/battle/headlessWalls";
import { createBattleSession } from "@/core";
import { MAX_HP } from "@/lib/combat";
import { stickmanCom } from "@/lib/stickmanIdleDamp";
import { createStickman } from "@/utils/createStickman";

describe("spawn settle symmetry", () => {
  it("arms and legs are mirrored around spawn X", () => {
    const x = 400;
    const y = 500;
    const r = 10;
    const s = createStickman(x, y, { render: { visible: false } });

    const xs = (label: string) =>
      s.bodies
        .filter((b) => b.label === label)
        .map((b) => b.position.x - x)
        .sort((a, b) => a - b);

    const leftArm = xs("Upper Left Arm");
    const rightArm = xs("Upper Right Arm");
    // Matter.Composites.stack сдвигает тела на +radius; важна зеркальность после symmetrize.
    expect(leftArm.length).toBe(rightArm.length);
    for (let i = 0; i < leftArm.length; i++) {
      expect(leftArm[i]!).toBeCloseTo(-rightArm[rightArm.length - 1 - i]!, 0);
    }

    const leftLeg = xs("Upper Left Leg")[0]!;
    const rightLeg = xs("Upper Right Leg")[0]!;
    expect(leftLeg).toBeCloseTo(-rightLeg, 0);
    // hipStance = 2r; stack +translate(+r) компенсирован стартом −r.
    expect(Math.abs(rightLeg - 2 * r)).toBeLessThan(2);
  });

  it("player does not corkscrew left in the first 2s of idle", () => {
    const arena = 1000;
    const spawnX = 360;
    const spawnY = 500;
    const player = createStickman(spawnX, spawnY, {
      render: { visible: false },
    });
    const opponent = createStickman(640, spawnY, {
      render: { visible: false },
    });
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
        { id: "player", composite: player, head: headP, maxHp: MAX_HP },
        { id: "opponent", composite: opponent, head: headO, maxHp: MAX_HP },
      ],
      playerCompositeId: player.id,
      opponentCompositeId: opponent.id,
      itemComposites: [],
    });
    session.beginBattle();
    const start = stickmanCom(player);

    let minDx = 0;
    for (let i = 0; i < 120; i++) {
      session.tick(1000 / 60);
      minDx = Math.min(minDx, stickmanCom(player).x - start.x);
    }

    expect(minDx).toBeGreaterThan(-18);
    expect(Math.abs(stickmanCom(player).x - start.x)).toBeLessThan(25);
    session.destroy();
  });
});
