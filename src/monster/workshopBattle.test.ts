import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { createBattleSession } from "@/core";
import { getAiProfile } from "@/battle/aiProfiles";
import { MAX_HP } from "@/lib/combat";
import { createStickman } from "@/utils/createStickman";
import { buildMonster, settleComposite } from "./buildMonster";
import { updateMonsterRopeConstraints } from "./linkTypes";
import { normalizeMonsterDef } from "./monsterTypes";

describe("workshop monster in battle", () => {
  it("connected rigid monster stays assembled under hard AI", () => {
    const def = normalizeMonsterDef({
      id: "workshop-ok",
      name: "OK",
      parts: [
        { x: 0, y: -28, radius: 20, isHead: true },
        { x: 0, y: 8, radius: 14, isHead: false },
        { x: -22, y: 36, radius: 12, isHead: false },
        { x: 22, y: 36, radius: 12, isHead: false },
      ],
      links: [
        { a: 0, b: 1, type: "rigid" },
        { a: 1, b: 2, type: "rigid" },
        { a: 1, b: 3, type: "rigid" },
      ],
      createdAt: 0,
    });

    const player = createStickman(280, 520, { render: { visible: false } });
    const built = buildMonster(def, 720, 520)!;
    settleComposite(built.composite);
    const head = built.head!;
    const playerHead = player.bodies.find((b) => b.label === "Head")!;

    const session = createBattleSession({
      arenaSize: 1000,
      fighters: [
        {
          id: "player",
          composite: player,
          head: playerHead,
          maxHp: MAX_HP,
        },
        {
          id: "bot",
          composite: built.composite,
          head,
          maxHp: 400,
          aiProfile: getAiProfile("hard"),
        },
      ],
      playerCompositeId: player.id,
      opponentCompositeId: built.composite.id,
      itemComposites: [],
    });
    session.beginBattle();

    for (let i = 0; i < 360; i++) {
      updateMonsterRopeConstraints(built.composite);
      session.tick(1000 / 60);
    }

    for (const link of def.links) {
      const a = built.composite.bodies[link.a]!;
      const b = built.composite.bodies[link.b]!;
      const dist = Matter.Vector.magnitude(
        Matter.Vector.sub(a.position, b.position),
      );
      const max =
        (a.circleRadius ?? 10) + (b.circleRadius ?? 10) + 90;
      expect(dist, `link ${link.a}-${link.b}`).toBeLessThan(max);
    }

    session.destroy();
  });

  it("orphan part drifts from head (documents fall-apart without links)", () => {
    const def = normalizeMonsterDef({
      id: "orphan",
      name: "Orphan",
      parts: [
        { x: 0, y: -20, radius: 20, isHead: true },
        { x: 0, y: 24, radius: 12, isHead: false },
        { x: 70, y: 24, radius: 12, isHead: false },
      ],
      links: [{ a: 0, b: 1, type: "rigid" }],
      createdAt: 0,
    });

    const player = createStickman(280, 520, { render: { visible: false } });
    const built = buildMonster(def, 720, 520)!;
    settleComposite(built.composite);
    const head = built.head!;
    const orphan = built.composite.bodies[2]!;
    const startDist = Matter.Vector.magnitude(
      Matter.Vector.sub(orphan.position, head.position),
    );

    const session = createBattleSession({
      arenaSize: 1000,
      fighters: [
        {
          id: "player",
          composite: player,
          head: player.bodies.find((b) => b.label === "Head")!,
          maxHp: MAX_HP,
        },
        {
          id: "bot",
          composite: built.composite,
          head,
          maxHp: 200,
          aiProfile: getAiProfile("hard"),
        },
      ],
      playerCompositeId: player.id,
      opponentCompositeId: built.composite.id,
      itemComposites: [],
    });
    session.beginBattle();
    for (let i = 0; i < 240; i++) {
      updateMonsterRopeConstraints(built.composite);
      session.tick(1000 / 60);
    }
    const endDist = Matter.Vector.magnitude(
      Matter.Vector.sub(orphan.position, head.position),
    );
    expect(endDist).toBeGreaterThan(startDist + 40);
    session.destroy();
  });
});
