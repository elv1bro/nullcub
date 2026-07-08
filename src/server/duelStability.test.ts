import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { MAX_HP, OPPONENT_MAX_HP } from "@/lib/combat";
import { GameRoom } from "./gameRoom";
import { InputRateLimiter } from "./inputValidator";

const TICK_MS = 1000 / 60;
const SIM_SECONDS = 60;
const TICK_COUNT = Math.ceil((SIM_SECONDS * 1000) / TICK_MS);

function startHeadlessDuel(roomId: string, opts?: { spawnItems?: boolean }) {
  const room = new GameRoom({
    roomId,
    spawnItems: opts?.spawnItems ?? true,
  });
  room.addClient({
    id: "player-id",
    name: "Host",
    fighterId: "player",
    send: () => {},
    limiter: new InputRateLimiter(),
  });
  room.addClient({
    id: "opponent-id",
    name: "Guest",
    fighterId: "opponent",
    send: () => {},
    limiter: new InputRateLimiter(),
  });
  room.setReady("player-id", true);
  room.setReady("opponent-id", true);
  return room;
}

function maxBodySpeed(session: import("@/core/battleSession").BattleSession): number {
  let max = 0;
  for (const body of Matter.Composite.allBodies(session.engine.world)) {
    if (body.isStatic) continue;
    max = Math.max(max, Matter.Vector.magnitude(body.velocity));
  }
  return max;
}

function getSession(room: GameRoom) {
  return (room as unknown as { session: import("@/core/battleSession").BattleSession })
    .session;
}

describe("headless duel stability", () => {
  it(`guest and host stay alive for ${SIM_SECONDS}s (idle)`, () => {
    // Без предметов: тест ловит self-damage от стен/пола, не item-chip.
    const room = startHeadlessDuel("idle-60s", { spawnItems: false });
    const session = getSession(room);

    let deathAt = -1;
    let deathSide: "player" | "opponent" | null = null;
    let peakSpeed = 0;

    for (let tick = 0; tick < TICK_COUNT; tick++) {
      room.tickBattle(TICK_MS);
      peakSpeed = Math.max(peakSpeed, maxBodySpeed(session));

      const playerHp = session.getHp("player");
      const opponentHp = session.getHp("opponent");
      if (playerHp <= 0 || opponentHp <= 0) {
        deathAt = tick;
        deathSide = playerHp <= 0 ? "player" : "opponent";
        break;
      }
    }

    const playerHp = session.getHp("player");
    const opponentHp = session.getHp("opponent");
    room.destroy();

    expect(
      deathAt,
      `${deathSide ?? "fighter"} died at ${((deathAt * TICK_MS) / 1000).toFixed(2)}s (player=${playerHp}, guest=${opponentHp}, peakV=${peakSpeed.toFixed(1)})`,
    ).toBe(-1);
    // Регресс: стены/пол не должны наносить урон — HP без ввода не меняется вообще.
    expect(playerHp, `player self-damaged to ${playerHp}`).toBe(MAX_HP);
    expect(opponentHp, `guest self-damaged to ${opponentHp}`).toBe(OPPONENT_MAX_HP);
    expect(peakSpeed).toBeLessThan(30);
  });

  it("move input pushes the head in the correct screen direction", () => {
    // Конвенция useMovementVectorRef: клавиша ВПРАВО даёт {x:-1}, ВВЕРХ даёт {y:+1};
    // moveBody инвертирует вектор. Итог: {x:-1} → голова летит вправо (+x).
    const room = startHeadlessDuel("controls-dir");
    const session = getSession(room);
    const head = session.getFighter("player")!.head;
    const x0 = head.position.x;

    for (let tick = 0; tick < 90; tick++) {
      room.handleInput("player-id", {
        seq: tick,
        t: tick * TICK_MS,
        move: { x: -1, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.tickBattle(TICK_MS);
    }

    const dx = head.position.x - x0;
    room.destroy();
    expect(dx, `right key must move head right, got dx=${dx.toFixed(1)}`).toBeGreaterThan(20);
  });

  it("fighters rushing into each other trade damage (hits work)", () => {
    const room = startHeadlessDuel("rush-hits");
    const session = getSession(room);

    let totalLost = 0;
    for (let tick = 0; tick < 15 * 60; tick++) {
      // сближение: player вправо ({x:-1} в legacy-конвенции), guest влево ({x:+1})
      room.handleInput("player-id", {
        seq: tick,
        t: tick * TICK_MS,
        move: { x: -1, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.handleInput("opponent-id", {
        seq: tick,
        t: tick * TICK_MS,
        move: { x: 1, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.tickBattle(TICK_MS);

      totalLost =
        MAX_HP - session.getHp("player") + (OPPONENT_MAX_HP - session.getHp("opponent"));
      if (totalLost > 50) break;
    }

    room.destroy();
    expect(totalLost, "no damage traded in 15s of rushing").toBeGreaterThan(50);
  });

  it(`guest and host stay alive for ${SIM_SECONDS}s (idle inputs)`, () => {
    const room = startHeadlessDuel("inputs-60s", { spawnItems: false });
    const session = getSession(room);
    let deathAt = -1;

    for (let tick = 0; tick < TICK_COUNT; tick++) {
      room.handleInput("player-id", {
        seq: tick,
        t: tick * TICK_MS,
        move: { x: 0, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.handleInput("opponent-id", {
        seq: tick,
        t: tick * TICK_MS,
        move: { x: 0, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.tickBattle(TICK_MS);

      if (session.getHp("player") <= 0 || session.getHp("opponent") <= 0) {
        deathAt = tick;
        break;
      }
    }

    const playerHp = session.getHp("player");
    const opponentHp = session.getHp("opponent");
    room.destroy();

    expect(deathAt, `death at ${((deathAt * TICK_MS) / 1000).toFixed(2)}s`).toBe(-1);
    expect(opponentHp).toBeGreaterThan(0);
    expect(playerHp).toBeGreaterThan(0);
  });

  it("reset stance runs for full duration and movement resumes after", () => {
    const room = startHeadlessDuel("reset-stance");
    const session = getSession(room);
    const fighter = session.getFighter("player")!;
    const ability = session.getAbilityState("player")!;
    expect(ability.poseSnap, "pose snapshot required for reset").not.toBeNull();

    session.setInput("player", {
      seq: 0,
      t: 0,
      move: { x: 0, y: 0 },
      grabL: false,
      grabR: false,
      dash: false,
      flip: false,
      freeze: false,
      reset: true,
    });
    room.tickBattle(TICK_MS);
    expect(ability.resetUntil, "reset should activate on server").toBeGreaterThan(0);

    let blockedTicks = fighter.inputBlocked ? 1 : 0;
    for (let tick = 1; tick < 70; tick++) {
      session.setInput("player", {
        seq: tick,
        t: tick * TICK_MS,
        move: { x: 0, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.tickBattle(TICK_MS);
      if (fighter.inputBlocked) blockedTicks++;
    }

    expect(blockedTicks, "reset should block input for most of duration").toBeGreaterThan(30);
    expect(blockedTicks).toBeLessThan(70);
    expect(fighter.inputBlocked, "input unblocked after reset ends").toBe(false);

    const head = fighter.head;
    const x0 = head.position.x;
    for (let tick = 0; tick < 90; tick++) {
      session.setInput("player", {
        seq: 200 + tick,
        t: (200 + tick) * TICK_MS,
        move: { x: -1, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      });
      room.tickBattle(TICK_MS);
    }

    const dx = head.position.x - x0;
    room.destroy();
    expect(dx, `movement after reset, dx=${dx.toFixed(1)}`).toBeGreaterThan(20);
  });

  it("does not duplicate dynamic bodies", () => {
    const room = startHeadlessDuel("body-count");
    const session = getSession(room);
    const ordered = (room as unknown as { orderedBodies: Matter.Body[] }).orderedBodies;
    const dynamic = Matter.Composite.allBodies(session.engine.world).filter(
      (b) => !b.isStatic,
    );

    expect(dynamic.length).toBe(ordered.length);
    room.destroy();
  });

  it("begins battle only after server settle (damage locked during spawn)", () => {
    const room = new GameRoom({ roomId: "settle" });
    room.addClient({
      id: "a",
      name: "A",
      fighterId: "player",
      send: () => {},
      limiter: new InputRateLimiter(),
    });
    room.addClient({
      id: "b",
      name: "B",
      fighterId: "opponent",
      send: () => {},
      limiter: new InputRateLimiter(),
    });
    room.setReady("a", true);
    room.setReady("b", true);

    const session = getSession(room);
    expect(session.isDamageLocked()).toBe(false);
    expect(session.getHp("player")).toBe(MAX_HP);
    expect(session.getHp("opponent")).toBe(OPPONENT_MAX_HP);

    room.destroy();
  });
});
