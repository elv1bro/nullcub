import { describe, expect, it } from "vitest";
import Matter from "matter-js";
import { createBattleSession, emptyInput } from "@/core";
import { getAiProfile } from "@/battle/aiProfiles";
import { createStickman } from "@/utils/createStickman";
import { tagStickmanHands } from "@/lib/grab/hands";
import { MAX_HP } from "@/lib/combat";
import {
  BATTLE_HARD_TIMEOUT_MS,
  BATTLE_TIME_LIMIT_MS,
  SUDDEN_DEATH_STEP,
  SUDDEN_DEATH_STEP_MS,
  suddenDeathMultiplier,
} from "@/lib/battleTuning";

function makeDuelSession() {
  const a = createStickman(300, 500, { render: { visible: false } });
  const b = createStickman(700, 500, { render: { visible: false } });
  tagStickmanHands(a, "a");
  tagStickmanHands(b, "b");
  const headA = a.bodies.find((x) => x.label === "Head")!;
  const headB = b.bodies.find((x) => x.label === "Head")!;
  return createBattleSession({
    arenaSize: 1000,
    fighters: [
      { id: "a", composite: a, head: headA, maxHp: MAX_HP },
      { id: "b", composite: b, head: headB, maxHp: MAX_HP },
    ],
    playerCompositeId: a.id,
    opponentCompositeId: b.id,
  });
}

describe("suddenDeathMultiplier", () => {
  it("is 1 before the time limit", () => {
    expect(suddenDeathMultiplier(0)).toBe(1);
    expect(suddenDeathMultiplier(BATTLE_TIME_LIMIT_MS - 1)).toBe(1);
  });

  it("grows by STEP each STEP_MS after the limit", () => {
    expect(suddenDeathMultiplier(BATTLE_TIME_LIMIT_MS)).toBeCloseTo(
      1 + SUDDEN_DEATH_STEP,
    );
    expect(
      suddenDeathMultiplier(BATTLE_TIME_LIMIT_MS + SUDDEN_DEATH_STEP_MS),
    ).toBeCloseTo(1 + SUDDEN_DEATH_STEP * 2);
    expect(
      suddenDeathMultiplier(BATTLE_TIME_LIMIT_MS + 3.5 * SUDDEN_DEATH_STEP_MS),
    ).toBeCloseTo(1 + SUDDEN_DEATH_STEP * 4);
  });
});

describe("BattleSession hard timeout", () => {
  it("ends the battle after BATTLE_HARD_TIMEOUT_MS; equal HP is a draw", () => {
    const session = makeDuelSession();
    // Толстые тики: физика не важна, важен sim-clock.
    const bigStep = 10_000;
    const steps = Math.ceil(BATTLE_HARD_TIMEOUT_MS / bigStep) + 1;
    for (let i = 0; i < steps; i++) {
      session.tick(bigStep, false);
    }
    expect(session.isBattleOver()).toBe(true);
    // Оба на полном HP — ничья.
    expect(session.resolveWinner()).toBeNull();
    session.destroy();
  });

  it("resolves winner by remaining HP on timeout", () => {
    const session = makeDuelSession();
    const fighterB = session.getFighter("b")!;
    fighterB.hp = MAX_HP / 2;
    const bigStep = 10_000;
    const steps = Math.ceil(BATTLE_HARD_TIMEOUT_MS / bigStep) + 1;
    for (let i = 0; i < steps; i++) {
      session.tick(bigStep, false);
    }
    expect(session.isBattleOver()).toBe(true);
    expect(session.resolveWinner()).toBe("a");
    session.destroy();
  });
});

describe("BattleSession destroy", () => {
  it("does not Engine.clear a shared external engine", () => {
    const engine = Matter.Engine.create();
    const marker = Matter.Bodies.rectangle(10, 10, 20, 20, {
      isStatic: true,
      label: "marker-wall",
    });
    Matter.Composite.add(engine.world, marker);

    const a = createStickman(300, 500, { render: { visible: false } });
    const b = createStickman(700, 500, { render: { visible: false } });
    tagStickmanHands(a, "a");
    tagStickmanHands(b, "b");
    Matter.Composite.add(engine.world, [a, b]);

    const session = createBattleSession({
      arenaSize: 1000,
      engine,
      compositesInWorld: true,
      fighters: [
        {
          id: "a",
          composite: a,
          head: a.bodies.find((x) => x.label === "Head")!,
          maxHp: MAX_HP,
        },
        {
          id: "b",
          composite: b,
          head: b.bodies.find((x) => x.label === "Head")!,
          maxHp: MAX_HP,
        },
      ],
      playerCompositeId: a.id,
      opponentCompositeId: b.id,
    });

    session.destroy();
    expect(
      Matter.Composite.allBodies(engine.world).some((b) => b.label === "marker-wall"),
    ).toBe(true);
    Matter.Engine.clear(engine);
  });
});

describe("BattleSession", () => {
  it("runs ticks and produces snapshot", () => {
    const a = createStickman(300, 500, { render: { visible: false } });
    const b = createStickman(700, 500, { render: { visible: false } });
    tagStickmanHands(a, "a");
    tagStickmanHands(b, "b");
    const headA = a.bodies.find((x) => x.label === "Head")!;
    const headB = b.bodies.find((x) => x.label === "Head")!;

    const session = createBattleSession({
      arenaSize: 1000,
      fighters: [
        {
          id: "a",
          composite: a,
          head: headA,
          maxHp: MAX_HP,
        },
        {
          id: "b",
          composite: b,
          head: headB,
          maxHp: MAX_HP,
        },
      ],
      playerCompositeId: a.id,
      opponentCompositeId: b.id,
    });

    session.setInput("a", {
      ...emptyInput(),
      move: { x: 1, y: 0 },
    });

    for (let i = 0; i < 120; i++) {
      session.tick();
    }

    const snap = session.snapshot();
    expect(snap.bodies.length).toBeGreaterThan(0);
    expect(snap.fighterHp.a).toBeLessThanOrEqual(MAX_HP);
    session.destroy();
  });

  it("clears AI grab input when intent releases", () => {
    const a = createStickman(300, 500, { render: { visible: false } });
    const b = createStickman(700, 500, { render: { visible: false } });
    tagStickmanHands(a, "a");
    tagStickmanHands(b, "bot");
    const headA = a.bodies.find((x) => x.label === "Head")!;
    const headB = b.bodies.find((x) => x.label === "Head")!;

    const session = createBattleSession({
      arenaSize: 1000,
      fighters: [
        { id: "a", composite: a, head: headA, maxHp: MAX_HP },
        {
          id: "bot",
          composite: b,
          head: headB,
          maxHp: MAX_HP,
          aiProfile: getAiProfile("hard"),
        },
      ],
      playerCompositeId: a.id,
      opponentCompositeId: b.id,
    });
    session.beginBattle();

    for (let i = 0; i < 300; i++) {
      session.tick(16, false);
    }

    const bot = session.getFighter("bot")!;
    expect(bot.input.grabL || bot.input.grabR).toBe(false);
    session.destroy();
  });
});
