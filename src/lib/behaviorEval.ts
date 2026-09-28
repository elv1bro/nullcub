/**
 * Числовая оценка поведения для агентов: без DOM, без «посмотри глазами».
 * Скрипт: yarn eval:behavior → test-artifacts/behavior-report.json
 */
import Matter from "matter-js";
import { createArenaWalls } from "@/battle/headlessWalls";
import { runHeadlessDuel } from "@/battle/headlessDuel";
import { BATTLE_GRAVITY, PLAYER_MOVE_SPEED } from "@/lib/battleTuning";
import { moveBody, toMoveInput } from "@/lib/moveBody";
import {
  dampStickmanLateralDrift,
  pullStickmanComToX,
} from "@/lib/stickmanIdleDamp";
import { runStarterIntegritySuite } from "@/monster/workshopIntegrity";
import { createStickman } from "@/utils/createStickman";

export type BehaviorCheck = {
  id: string;
  ok: boolean;
  value: number;
  limit: number;
  /** 'lt' = value must be < limit; 'gt' = value must be > limit; 'lte'/'gte' */
  cmp: "lt" | "lte" | "gt" | "gte";
  unit?: string;
  detail?: string;
};

export type BehaviorReport = {
  ok: boolean;
  generatedAt: string;
  durationMs: number;
  checks: BehaviorCheck[];
};

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

function pass(check: Omit<BehaviorCheck, "ok">): BehaviorCheck {
  const ok =
    check.cmp === "lt"
      ? check.value < check.limit
      : check.cmp === "lte"
        ? check.value <= check.limit
        : check.cmp === "gt"
          ? check.value > check.limit
          : check.value >= check.limit;
  return { ...check, ok };
}

function evalIdle(): BehaviorCheck[] {
  const { engine, stickman, head } = setupStickman();
  for (let i = 0; i < 30; i++) Matter.Engine.update(engine, STEP_MS);
  const startComX = massComX(stickman);
  const startHeadY = head.position.y;
  const anchorX = startComX;

  for (let i = 0; i < 30 * 60; i++) {
    dampStickmanLateralDrift(stickman, 0.22);
    pullStickmanComToX(stickman, anchorX, 0.0007);
    Matter.Engine.update(engine, STEP_MS);
  }

  const comDrift = Math.abs(massComX(stickman) - startComX);
  const fell = head.position.y - startHeadY;
  Matter.Engine.clear(engine);

  return [
    pass({
      id: "idle_symmetry_com",
      value: Math.round(comDrift * 10) / 10,
      limit: 30,
      cmp: "lt",
      unit: "px",
      detail: "Idle 30s: |COM.x − spawn|",
    }),
    pass({
      id: "idle_falls",
      value: Math.round(fell * 10) / 10,
      limit: 20,
      cmp: "gt",
      unit: "px",
      detail: "Idle 30s: head drops downward",
    }),
  ];
}

function evalMove(): BehaviorCheck[] {
  function travelX(dirX: number): number {
    const { engine, stickman, head } = setupStickman();
    settle(engine, stickman, 45);
    const startX = head.position.x;
    const apply = moveBody(head);
    const fakeEvent = {
      delta: STEP_MS,
    } as unknown as Matter.IEventTimestamped<Matter.Engine>;
    for (let i = 0; i < 90; i++) {
      apply(fakeEvent, toMoveInput({ x: dirX, y: 0 }), PLAYER_MOVE_SPEED);
      Matter.Engine.update(engine, STEP_MS);
    }
    const dx = head.position.x - startX;
    Matter.Engine.clear(engine);
    return dx;
  }

  function travelY(dirY: number): number {
    const { engine, stickman, head } = setupStickman();
    settle(engine, stickman, 45);
    const startY = head.position.y;
    const apply = moveBody(head);
    const fakeEvent = {
      delta: STEP_MS,
    } as unknown as Matter.IEventTimestamped<Matter.Engine>;
    for (let i = 0; i < 90; i++) {
      apply(fakeEvent, toMoveInput({ x: 0, y: dirY }), PLAYER_MOVE_SPEED);
      Matter.Engine.update(engine, STEP_MS);
    }
    const dy = head.position.y - startY;
    Matter.Engine.clear(engine);
    return dy;
  }

  const right = travelX(1);
  const left = travelX(-1);
  const down = travelY(1);
  const up = travelY(-1);
  const lrBalance = Math.abs(Math.abs(right) - Math.abs(left));

  return [
    pass({
      id: "move_right",
      value: Math.round(right * 10) / 10,
      limit: 40,
      cmp: "gt",
      unit: "px",
      detail: "Small +X for 1.5s",
    }),
    pass({
      id: "move_left",
      value: Math.round(left * 10) / 10,
      limit: -40,
      cmp: "lt",
      unit: "px",
      detail: "Small −X for 1.5s",
    }),
    pass({
      id: "move_lr_balance",
      value: Math.round(lrBalance * 10) / 10,
      limit: 40,
      cmp: "lt",
      unit: "px",
      detail: "||dxR| − |dxL||",
    }),
    pass({
      id: "move_down",
      value: Math.round(down * 10) / 10,
      limit: 25,
      cmp: "gt",
      unit: "px",
      detail: "Small +Y for 1.5s",
    }),
    pass({
      id: "move_up",
      value: Math.round(up * 10) / 10,
      limit: -15,
      cmp: "lt",
      unit: "px",
      detail: "Small −Y for 1.5s",
    }),
  ];
}

function evalWorkshopIntegrity(): BehaviorCheck[] {
  const results = runStarterIntegritySuite(300);
  const failed = results.filter((r) => !r.ok);
  return [
    pass({
      id: "workshop_integrity",
      value: failed.length,
      limit: 0,
      cmp: "lte",
      unit: "broken_starters",
      detail:
        failed.length === 0
          ? "All starters hold under hard AI"
          : failed.map((f) => `${f.name}:${f.broken.join(",")}`).join(" | "),
    }),
  ];
}

function evalCombatPace(): BehaviorCheck[] {
  const durations: number[] = [];
  for (let seed = 1; seed <= 8; seed++) {
    const out = runHeadlessDuel("easy", "hard", seed);
    durations.push(out.durationMs / 1000);
  }
  durations.sort((a, b) => a - b);
  const mid = Math.floor(durations.length / 2);
  const median =
    durations.length % 2 === 0
      ? (durations[mid - 1]! + durations[mid]!) / 2
      : durations[mid]!;

  return [
    pass({
      id: "combat_pace_median_min",
      value: Math.round(median * 10) / 10,
      limit: 8,
      cmp: "gte",
      unit: "s",
      detail: "easy vs hard median duration (not instant)",
    }),
    pass({
      id: "combat_pace_median_max",
      value: Math.round(median * 10) / 10,
      limit: 55,
      cmp: "lte",
      unit: "s",
      detail: "easy vs hard median duration (not endless)",
    }),
  ];
}

/** Полный прогон метрик поведения (headless). */
export function evaluateBehavior(): BehaviorReport {
  const t0 = Date.now();
  const checks: BehaviorCheck[] = [
    ...evalIdle(),
    ...evalMove(),
    ...evalWorkshopIntegrity(),
    ...evalCombatPace(),
  ];
  return {
    ok: checks.every((c) => c.ok),
    generatedAt: new Date().toISOString(),
    durationMs: Date.now() - t0,
    checks,
  };
}
