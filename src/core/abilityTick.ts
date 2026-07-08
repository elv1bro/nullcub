import Matter, { Body, Composite, Vector, type Engine } from "matter-js";
import type { PoseSnapshot } from "@/lib/ragdollPoseReset";
import {
  DASH_COOLDOWN_MS,
  DASH_DURATION_MS,
  DASH_SPEED_MULT,
  FLIP_ANGULAR_VEL,
  FLIP_COOLDOWN_MS,
  BRACE_COOLDOWN_MS,
  BRACE_DURATION_MS,
  RESET_COOLDOWN_MS,
  RESET_DURATION_MS,
  PLAYER_MOVE_SPEED,
} from "@/lib/battleTuning";
import {
  activateBraceBurst,
  restoreBraceStiffness,
  stepBraceStance,
} from "@/lib/braceStance";
import { stepPoseReset } from "@/lib/ragdollPoseReset";
import { moveBody } from "@/lib/moveBody";
import type { NetInputPayload } from "@/net/protocol";
import type { CoreFighterRuntime } from "./types";

export interface AbilityRuntimeState {
  lastDash: number;
  dashUntil: number;
  lastFlip: number;
  lastBrace: number;
  braceUntil: number;
  braceStiffness: ReturnType<typeof activateBraceBurst> | null;
  lastReset: number;
  resetUntil: number;
  resetStart: number;
  poseSnap: PoseSnapshot | null;
}

export function createAbilityState(poseSnap: PoseSnapshot | null = null): AbilityRuntimeState {
  return {
    lastDash: 0,
    dashUntil: 0,
    lastFlip: 0,
    lastBrace: 0,
    braceUntil: 0,
    braceStiffness: null,
    lastReset: 0,
    resetUntil: 0,
    resetStart: 0,
    poseSnap,
  };
}

function applyFlip(composite: Composite, move: Vector, rng: () => number): void {
  let sign = rng() > 0.5 ? 1 : -1;
  if (Math.abs(move.x) > 0.1) sign = move.x > 0 ? 1 : -1;
  else if (Math.abs(move.y) > 0.1) sign = move.y > 0 ? -1 : 1;
  for (const body of composite.bodies) {
    const wobble = 0.92 + rng() * 0.16;
    Body.setAngularVelocity(body, sign * FLIP_ANGULAR_VEL * wobble);
  }
}

function cooldownReady(lastUse: number, now: number, cooldownMs: number): boolean {
  return lastUse === 0 || now - lastUse >= cooldownMs;
}

export function cooldownRemaining(
  lastUse: number,
  now: number,
  cooldownMs: number,
): number {
  if (lastUse === 0) return 0;
  return Math.max(0, cooldownMs - (now - lastUse));
}

export function tickFighterAbilities(
  fighter: CoreFighterRuntime,
  ability: AbilityRuntimeState,
  event: Matter.IEventTimestamped<Engine>,
  now: number,
  rng: () => number,
): void {
  const composite = fighter.composite;
  const head = fighter.head;
  const input = fighter.input;
  const move = Vector.create(input.move.x, input.move.y);

  const braceActive = ability.braceUntil > now;
  let resetActive = ability.resetUntil > now;

  fighter.braceActive = braceActive;
  fighter.moveSpeedMult =
    ability.dashUntil > now ? DASH_SPEED_MULT : 1;

  if (braceActive) {
    stepBraceStance(composite);
  } else if (ability.braceStiffness) {
    restoreBraceStiffness(ability.braceStiffness);
    ability.braceStiffness = null;
  }

  if (input.dash && !resetActive && cooldownReady(ability.lastDash, now, DASH_COOLDOWN_MS)) {
    ability.lastDash = now;
    ability.dashUntil = now + DASH_DURATION_MS;
  }

  if (input.flip && !resetActive && cooldownReady(ability.lastFlip, now, FLIP_COOLDOWN_MS)) {
    ability.lastFlip = now;
    applyFlip(composite, move, rng);
  }

  if (
    input.freeze &&
    !resetActive &&
    cooldownReady(ability.lastBrace, now, BRACE_COOLDOWN_MS) &&
    ability.braceUntil <= now
  ) {
    ability.lastBrace = now;
    ability.braceUntil = now + BRACE_DURATION_MS;
    ability.braceStiffness = activateBraceBurst(composite);
  }

  if (
    input.reset &&
    ability.poseSnap &&
    !resetActive &&
    cooldownReady(ability.lastReset, now, RESET_COOLDOWN_MS) &&
    ability.resetUntil <= now
  ) {
    ability.braceUntil = 0;
    if (ability.braceStiffness) {
      restoreBraceStiffness(ability.braceStiffness);
      ability.braceStiffness = null;
    }
    ability.lastReset = now;
    ability.resetStart = now;
    ability.resetUntil = now + RESET_DURATION_MS;
    resetActive = true;
  }

  fighter.inputBlocked = resetActive;

  if (resetActive && ability.poseSnap) {
    const progress = (now - ability.resetStart) / RESET_DURATION_MS;
    stepPoseReset(composite, ability.poseSnap, progress);
  }

  if (!resetActive && !fighter.aiProfile) {
    const speed = PLAYER_MOVE_SPEED * fighter.moveSpeedMult;
    // В brace чуть слабее тяга — не «залипание», а ощущение стойки.
    const braceMult = braceActive ? 0.72 : 1;
    if (move.x !== 0 || move.y !== 0) {
      moveBody(head)(event, move, speed * braceMult);
    }
  }
}

export function netInputFromFlags(
  move: Vector,
  grabL: boolean,
  grabR: boolean,
  flags: { dash?: boolean; flip?: boolean; freeze?: boolean; reset?: boolean },
  seq: number,
  t: number,
): NetInputPayload {
  return {
    seq,
    t,
    move: { x: move.x, y: move.y },
    grabL,
    grabR,
    dash: flags.dash ?? false,
    flip: flags.flip ?? false,
    freeze: flags.freeze ?? false,
    reset: flags.reset ?? false,
  };
}

export const emptyInput = (): NetInputPayload => ({
  seq: 0,
  t: 0,
  move: { x: 0, y: 0 },
  grabL: false,
  grabR: false,
  dash: false,
  flip: false,
  freeze: false,
  reset: false,
});
