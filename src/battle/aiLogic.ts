import { Body, type Bounds, Vector, type Composite } from "matter-js";
import {
  AI_APPROACH_SPEED,
  AI_CIRCLE_SPEED,
  AI_LUNGE_SPEED,
  AI_STRAFE_SPEED,
  DASH_SPEED_MULT,
  FLIP_ANGULAR_VEL,
  BRACE_DURATION_MS,
  BATTLE_OPENING_BRAWL_MS,
  GRAB_ENABLED,
} from "@/lib/battleTuning";
import {
  activateBraceBurst,
  restoreBraceStiffness,
  stepBraceStance,
} from "@/lib/braceStance";
import type { AiProfile } from "./aiProfiles";

const BASE_APPROACH = AI_APPROACH_SPEED;
const BASE_LUNGE = AI_LUNGE_SPEED;
const BASE_STRAFE = AI_STRAFE_SPEED;
const BASE_CIRCLE = AI_CIRCLE_SPEED;
const STRAFE_RANGE = 200;
const CIRCLE_RANGE = 340;
const STRAFE_FLIP_MS = 700;
const WALL_MARGIN = 90;

export interface BotBrainState {
  lastLunge: number;
  lastStrafeFlip: number;
  strafeDir: number;
  grabSide: "left" | "right" | null;
  grabUntil: number;
  grabCooldownUntil: number;
  /** Sim/wall clock старта боя — для opening brawl без хвата. */
  battleStartMs?: number;
  lastDash: number;
  dashUntil: number;
  lastFlip: number;
  lastBrace: number;
  braceUntil: number;
  braceStiffness: ReturnType<typeof activateBraceBurst> | null;
}

export function createBotBrainState(): BotBrainState {
  return {
    lastLunge: 0,
    lastStrafeFlip: 0,
    strafeDir: 1,
    grabSide: null,
    grabUntil: 0,
    grabCooldownUntil: 0,
    lastDash: 0,
    dashUntil: 0,
    lastFlip: 0,
    lastBrace: 0,
    braceUntil: 0,
    braceStiffness: null,
  };
}

export interface BotMoveIntent {
  worldMove: Vector;
  speed: number;
  grabL: boolean;
  grabR: boolean;
  speedMult: number;
}

function applyAimNoise(dir: Vector, amount: number): Vector {
  if (amount <= 0) return dir;
  const angle =
    (Math.random() - 0.5) * amount * Math.PI * 0.55;
  const cos = Math.cos(angle);
  const sin = Math.sin(angle);
  return Vector.normalise({
    x: dir.x * cos - dir.y * sin,
    y: dir.x * sin + dir.y * cos,
  });
}

export function computeBotMoveIntent(
  profile: AiProfile,
  state: BotBrainState,
  botHead: Body,
  playerHead: Body,
  bounds: Bounds | undefined,
  now: number,
): BotMoveIntent {
  const toPlayer = Vector.sub(playerHead.position, botHead.position);
  const dist = Vector.magnitude(toPlayer);
  if (state.battleStartMs == null) state.battleStartMs = now;
  const battleElapsed = now - state.battleStartMs;
  let grabL = false;
  let grabR = false;

  if (GRAB_ENABLED) {
  if (state.grabSide && now < state.grabUntil) {
    if (state.grabSide === "left") grabL = true;
    else grabR = true;
  } else if (state.grabSide) {
    state.grabSide = null;
    state.grabCooldownUntil = now + profile.grabCooldownMs;
  }

  const canConsiderGrab =
    profile.grabRange > 0 &&
    profile.grabChance > 0 &&
    profile.grabCooldownMs > 0 &&
    battleElapsed >= BATTLE_OPENING_BRAWL_MS &&
    dist < profile.grabRange &&
    dist > 45 &&
    now >= state.grabCooldownUntil &&
    !state.grabSide &&
    Math.random() < profile.grabChance;

  if (canConsiderGrab) {
    state.grabSide = Math.random() > 0.5 ? "left" : "right";
    state.grabUntil = now + profile.grabHoldMs;
    state.grabCooldownUntil = now + profile.grabCooldownMs;
    if (state.grabSide === "left") grabL = true;
    else grabR = true;
  }
  }

  if (dist < 1e-4) {
    return {
      worldMove: Vector.create(0, 1),
      speed: BASE_APPROACH * profile.speedMult,
      grabL,
      grabR,
      speedMult: dashSpeedMult(profile, state, now),
    };
  }

  if (now - state.lastStrafeFlip > STRAFE_FLIP_MS) {
    state.lastStrafeFlip = now;
    state.strafeDir *= -1;
    if (Math.random() < profile.mistakeRate) {
      state.strafeDir *= -1;
    }
  }

  let worldDir = Vector.normalise(toPlayer);
  const perp = Vector.create(
    -worldDir.y * state.strafeDir,
    worldDir.x * state.strafeDir,
  );

  let speed = BASE_APPROACH * profile.speedMult;
  const dashMult = dashSpeedMult(profile, state, now);

  if (
    dist < profile.lungeRange &&
    now - state.lastLunge > profile.lungeCooldownMs
  ) {
    state.lastLunge = now;
    speed = BASE_LUNGE * profile.speedMult * dashMult;
    // Само-спин на рывке убран: вращение подставляло СВОЮ голову (×1.6 зона)
    // под кулаки жертвы — агрессивные боты проигрывали пассивным.
  } else if (dist < STRAFE_RANGE) {
    worldDir = Vector.normalise(
      Vector.add(Vector.mult(worldDir, 0.55), Vector.mult(perp, 0.45)),
    );
    speed = BASE_STRAFE * profile.speedMult * dashMult;
  } else if (dist < CIRCLE_RANGE) {
    worldDir = Vector.normalise(
      Vector.add(Vector.mult(worldDir, 0.45), Vector.mult(perp, 0.55)),
    );
    speed = BASE_CIRCLE * profile.speedMult * dashMult;
  } else if (dist > 420) {
    speed = (BASE_APPROACH + 8) * profile.speedMult * dashMult;
  }

  if (bounds) {
    const wallBias = { x: 0, y: 0 };
    if (botHead.position.x < bounds.min.x + WALL_MARGIN) wallBias.x += 0.7;
    if (botHead.position.x > bounds.max.x - WALL_MARGIN) wallBias.x -= 0.7;
    if (botHead.position.y < bounds.min.y + WALL_MARGIN) wallBias.y += 0.5;
    if (botHead.position.y > bounds.max.y - WALL_MARGIN) wallBias.y -= 0.5;
    if (wallBias.x !== 0 || wallBias.y !== 0) {
      worldDir = Vector.normalise(Vector.add(worldDir, wallBias));
    }
  }

  worldDir = applyAimNoise(worldDir, profile.aimNoise);

  return {
    worldMove: worldDir,
    speed,
    grabL,
    grabR,
    speedMult: dashMult,
  };
}

function dashSpeedMult(
  profile: AiProfile,
  state: BotBrainState,
  now: number,
): number {
  if (!profile.useDash) return 1;
  if (now < state.dashUntil) return DASH_SPEED_MULT;
  if (now - state.lastDash >= profile.dashCooldownMs && Math.random() < (profile.useDash ? 0.022 : 0)) {
    state.lastDash = now;
    state.dashUntil = now + profile.dashDurationMs;
    return DASH_SPEED_MULT;
  }
  return 1;
}

/** Flip / brace — вызывается раз в кадр из хука бота. */
export function tickBotAbilities(
  profile: AiProfile,
  state: BotBrainState,
  botComposite: Composite | undefined,
  botHead: Body | undefined,
  playerHead: Body | undefined,
  now: number,
): void {
  if (!botComposite || !botHead || !playerHead) return;

  // Паритет с tickFighterAbilities: brace damp каждый кадр, иначе бот
  // «взрывается» кручением, пока ещё двигается.
  if (state.braceUntil > now) {
    stepBraceStance(botComposite);
    return;
  }
  if (state.braceStiffness) {
    restoreBraceStiffness(state.braceStiffness);
    state.braceStiffness = null;
  }

  const dist = Vector.magnitude(
    Vector.sub(playerHead.position, botHead.position),
  );

  if (
    profile.useBrace &&
    dist < 240 &&
    now - state.lastBrace > profile.braceCooldownMs &&
    Math.random() < 0.006
  ) {
    state.lastBrace = now;
    state.braceUntil = now + BRACE_DURATION_MS;
    state.braceStiffness = activateBraceBurst(botComposite);
    return;
  }

  if (
    profile.useFlip &&
    dist < 260 &&
    now - state.lastFlip > profile.flipCooldownMs &&
    Math.random() < (profile.id === "boss" ? 0.014 : 0.008)
  ) {
    state.lastFlip = now;
    const toPlayer = Vector.sub(playerHead.position, botHead.position);
    let sign = toPlayer.x >= 0 ? 1 : -1;
    if (Math.random() < profile.mistakeRate) sign *= -1;
    for (const body of botComposite.bodies) {
      Body.setAngularVelocity(body, sign * FLIP_ANGULAR_VEL * (0.9 + Math.random() * 0.2));
    }
  }
}
