import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { createArenaWalls } from "@/battle/headlessWalls";
import { BATTLE_GRAVITY, PLAYER_MOVE_SPEED } from "@/lib/battleTuning";
import { moveBody, toMoveInput } from "@/lib/moveBody";
import {
  dampStickmanLateralDrift,
  pullStickmanComToX,
} from "@/lib/stickmanIdleDamp";
import { createStickman } from "./createStickman";

const ARENA = 1000;
const STEP_MS = 1000 / 60;
const SPAWN_X = 500;
const SPAWN_Y = 420;

function massComX(composite: Matter.Composite): number {
  let mx = 0;
  let m = 0;
  for (const b of composite.bodies) {
    mx += b.position.x * b.mass;
    m += b.mass;
  }
  return mx / Math.max(m, 1e-6);
}

function setupStickman() {
  const engine = Matter.Engine.create({ gravity: { ...BATTLE_GRAVITY } });
  const bounds = Matter.Bounds.create([
    { x: 0, y: 0 },
    { x: ARENA, y: ARENA },
  ]);
  const walls = createArenaWalls(bounds, ARENA);
  const stickman = createStickman(SPAWN_X, SPAWN_Y, {
    render: { visible: false },
  });
  Matter.World.add(engine.world, [walls, stickman]);
  const head = stickman.bodies.find((b) => b.label === "Head")!;
  return { engine, stickman, head };
}

function settle(
  engine: Matter.Engine,
  stickman: Matter.Composite,
  ticks: number,
): void {
  for (let i = 0; i < ticks; i++) {
    Matter.Engine.update(engine, STEP_MS);
    for (const b of stickman.bodies) {
      Matter.Body.setVelocity(b, { x: 0, y: 0 });
      Matter.Body.setAngularVelocity(b, 0);
    }
  }
}

describe("stickman control feel", () => {
  it("spawn limbs are mirrored about spawn x", () => {
    const stickman = createStickman(SPAWN_X, SPAWN_Y);
    const pairs: Array<[string, string, "flip" | "same"]> = [
      ["Upper Left Arm", "Upper Right Arm", "flip"],
      ["Lower Left Arm", "Lower Right Arm", "flip"],
      ["Upper Left Leg", "Upper Right Leg", "same"],
      ["Lower Left Leg", "Lower Right Leg", "same"],
    ];
    for (const [leftLabel, rightLabel, mode] of pairs) {
      const left = stickman.bodies.filter((b) => b.label === leftLabel);
      const right = stickman.bodies.filter((b) => b.label === rightLabel);
      expect(left.length).toBe(right.length);
      for (let i = 0; i < left.length; i++) {
        const l = left[i]!;
        const r = mode === "flip" ? right[right.length - 1 - i]! : right[i]!;
        expect(l.position.x + r.position.x).toBeCloseTo(2 * SPAWN_X, 1);
        expect(l.position.y).toBeCloseTo(r.position.y, 1);
      }
    }
    expect(Math.abs(massComX(stickman) - SPAWN_X)).toBeLessThan(2);
  });

  it("spawn legs hang down uncrossed with clear hip stance", () => {
    const stickman = createStickman(SPAWN_X, SPAWN_Y);
    const leftLeg = stickman.bodies.filter((b) =>
      b.label.includes("Left Leg"),
    );
    const rightLeg = stickman.bodies.filter((b) =>
      b.label.includes("Right Leg"),
    );
    const leftFoot = leftLeg.reduce((a, b) =>
      a.position.y > b.position.y ? a : b,
    );
    const rightFoot = rightLeg.reduce((a, b) =>
      a.position.y > b.position.y ? a : b,
    );
    const leftHip = leftLeg.reduce((a, b) =>
      a.position.y < b.position.y ? a : b,
    );
    const rightHip = rightLeg.reduce((a, b) =>
      a.position.y < b.position.y ? a : b,
    );

    // Левая нога слева от центра, правая справа — не перекрёст.
    expect(leftFoot.position.x).toBeLessThan(SPAWN_X - 8);
    expect(rightFoot.position.x).toBeGreaterThan(SPAWN_X + 8);
    expect(leftFoot.position.x).toBeLessThan(rightFoot.position.x);

    // Ноги вниз от таза, не T-pose.
    expect(leftFoot.position.y).toBeGreaterThan(leftHip.position.y + 40);
    expect(rightFoot.position.y).toBeGreaterThan(rightHip.position.y + 40);

    // Ширина стойки предсказуема (~2–3 диаметра сегмента).
    const stance = rightHip.position.x - leftHip.position.x;
    expect(stance).toBeGreaterThan(20);
    expect(stance).toBeLessThan(60);
  });

  it("idle 30s: falls but stays laterally symmetric", () => {
    const { engine, stickman, head } = setupStickman();
    for (let i = 0; i < 30; i++) Matter.Engine.update(engine, STEP_MS);

    const startHeadX = head.position.x;
    const startComX = massComX(stickman);
    const anchorX = startComX;

    for (let i = 0; i < 30 * 60; i++) {
      // Как в BattleSession при нулевом вводе.
      dampStickmanLateralDrift(stickman, 0.22);
      pullStickmanComToX(stickman, anchorX, 0.0007);
      Matter.Engine.update(engine, STEP_MS);
    }

    const headDrift = head.position.x - startHeadX;
    const comDrift = massComX(stickman) - startComX;
    // Падает вниз — ок; боковой увод должен быть маленьким (голова шумнее COM).
    expect(Math.abs(headDrift)).toBeLessThan(55);
    expect(Math.abs(comDrift)).toBeLessThan(30);
    // Голова ниже спавна (реально «падает»).
    expect(head.position.y).toBeGreaterThan(SPAWN_Y + 20);

    Matter.Engine.clear(engine);
  });

  it("small left/right input moves predictably (near opposite dx)", () => {
    function travel(dirX: number): number {
      const { engine, stickman, head } = setupStickman();
      settle(engine, stickman, 45);
      const startX = head.position.x;
      const apply = moveBody(head);
      const fakeEvent = {
        delta: STEP_MS,
      } as unknown as Matter.IEventTimestamped<Matter.Engine>;

      for (let i = 0; i < 90; i++) {
        apply(
          fakeEvent,
          toMoveInput({ x: dirX, y: 0 }),
          PLAYER_MOVE_SPEED,
        );
        Matter.Engine.update(engine, STEP_MS);
      }
      const dx = head.position.x - startX;
      Matter.Engine.clear(engine);
      return dx;
    }

    const right = travel(1);
    const left = travel(-1);

    expect(right).toBeGreaterThan(40);
    expect(left).toBeLessThan(-40);
    // Симметрия: |dx| близки (допуск на solver).
    expect(Math.abs(Math.abs(right) - Math.abs(left))).toBeLessThan(40);
  });

  it("small up/down input moves predictably", () => {
    function travel(dirY: number): number {
      const { engine, stickman, head } = setupStickman();
      settle(engine, stickman, 45);
      const startY = head.position.y;
      const apply = moveBody(head);
      const fakeEvent = {
        delta: STEP_MS,
      } as unknown as Matter.IEventTimestamped<Matter.Engine>;

      for (let i = 0; i < 90; i++) {
        apply(
          fakeEvent,
          toMoveInput({ x: 0, y: dirY }),
          PLAYER_MOVE_SPEED,
        );
        Matter.Engine.update(engine, STEP_MS);
      }
      const dy = head.position.y - startY;
      Matter.Engine.clear(engine);
      return dy;
    }

    const down = travel(1);
    const up = travel(-1);

    expect(down).toBeGreaterThan(25);
    expect(up).toBeLessThan(-15);
  });
});
