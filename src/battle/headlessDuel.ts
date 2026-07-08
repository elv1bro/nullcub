import Matter from "matter-js";
import type { AiDifficultyId } from "./aiProfiles";
import { getAiProfile } from "./aiProfiles";
import { createStickman } from "@/utils/createStickman";
import { tagStickmanHands } from "@/lib/grab/hands";
import { MAX_HP } from "@/lib/combat";
import { BATTLE_HARD_TIMEOUT_MS } from "@/lib/battleTuning";
import {
  createBattleSession,
  createSeededClock,
  type BattleSession,
} from "@/core";

export const HEADLESS_ARENA = 1000;
export const HEADLESS_BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: HEADLESS_ARENA, y: HEADLESS_ARENA },
]);

const STEP_MS = 1000 / 60;
/** Синхронно с жёстким тайм-аутом боя — не обрезаем раньше sudden death. */
const MAX_STEPS = Math.ceil(BATTLE_HARD_TIMEOUT_MS / STEP_MS);
/** Ближе друг к другу → меньше «раскачки», больше KO до тайм-аута. */
const SPAWN_SPREAD = 140;

export interface HeadlessDuelOutcome {
  winner: AiDifficultyId | "draw";
  durationMs: number;
  steps: number;
  /** HP по id участников дуэли (только два ключа из AiDifficultyId). */
  hpLeft: Partial<Record<AiDifficultyId, number>>;
}

function spawnAiFighter(id: AiDifficultyId, x: number, y: number) {
  const profile = getAiProfile(id);
  const composite = createStickman(x, y, {
    render: { fillStyle: "#444", visible: false },
  });
  tagStickmanHands(composite, id);
  const head = composite.bodies.find((b) => b.label === "Head");
  if (!head) throw new Error("stickman missing head");
  return {
    id,
    composite,
    head,
    maxHp: MAX_HP,
    aiProfile: profile,
  };
}

export function runHeadlessDuel(
  leftId: AiDifficultyId,
  rightId: AiDifficultyId,
  seed = 0,
): HeadlessDuelOutcome {
  const left = spawnAiFighter(
    leftId,
    HEADLESS_ARENA / 2 - SPAWN_SPREAD,
    HEADLESS_ARENA / 2,
  );
  const right = spawnAiFighter(
    rightId,
    HEADLESS_ARENA / 2 + SPAWN_SPREAD,
    HEADLESS_ARENA / 2,
  );

  const clock = createSeededClock(seed || 1, 1000);
  const session: BattleSession = createBattleSession(
    {
      arenaSize: HEADLESS_ARENA,
      fighters: [left, right],
      playerCompositeId: left.composite.id,
      opponentCompositeId: right.composite.id,
      battleStartMs: 1000,
    },
    clock,
  );
  session.beginBattle();

  let steps = 0;
  while (steps < MAX_STEPS && !session.isBattleOver()) {
    session.tick(STEP_MS);
    steps++;
  }

  const winner = session.resolveWinner();
  const hpLeft: Partial<Record<AiDifficultyId, number>> = {
    [leftId]: Math.round(session.getHp(leftId)),
    [rightId]: Math.round(session.getHp(rightId)),
  };

  session.destroy();

  let outcome: AiDifficultyId | "draw" = "draw";
  if (winner === leftId) outcome = leftId;
  else if (winner === rightId) outcome = rightId;
  else if (hpLeft[leftId]! > hpLeft[rightId]!) outcome = leftId;
  else if (hpLeft[rightId]! > hpLeft[leftId]!) outcome = rightId;

  return {
    winner: outcome,
    durationMs: steps * STEP_MS,
    steps,
    hpLeft,
  };
}

/** Экспорт для тестов ядра. */
export { createBattleSession, createSeededClock };
