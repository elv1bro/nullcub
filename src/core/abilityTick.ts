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
import { loadoutAllowsAbility } from "@/loadout/loadoutGate";
import {
  applyLoadoutCastEffect,
  loadoutSlotAbilityCooldownMs,
  resolveLoadoutCast,
} from "@/loadout/castAbility";
import { ABILITY_META } from "@/loadout/catalogMeta";
import type { AbilityId } from "@/loadout/types";
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
  lastSlot0: number;
  slot0Until: number;
  lastSlot0Id: AbilityId | null;
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
    lastSlot0: 0,
    slot0Until: 0,
    lastSlot0Id: null,
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

function tryCastSlot0(
  fighter: CoreFighterRuntime,
  ability: AbilityRuntimeState,
  move: Vector,
  now: number,
  rng: () => number,
  resetActive: boolean,
): void {
  if (resetActive || !fighter.input.abilitySlot) return;
  const queue: AbilityId[] =
    fighter.castAbilities && fighter.castAbilities.length > 0
      ? fighter.castAbilities
      : fighter.loadout?.abilities[0]
        ? [fighter.loadout.abilities[0]]
        : [];
  if (!queue.length) return;

  // Каст первой готовой из очереди (тест-арена: несколько способностей).
  for (const slotId of queue) {
    const resolved = resolveLoadoutCast(slotId);
    if (!resolved.ok) continue;

    if (resolved.kind === "base") {
      if (
        resolved.base === "dash" &&
        cooldownReady(ability.lastDash, now, DASH_COOLDOWN_MS)
      ) {
        ability.lastDash = now;
        ability.dashUntil = now + DASH_DURATION_MS;
        return;
      }
      if (
        resolved.base === "flip" &&
        cooldownReady(ability.lastFlip, now, FLIP_COOLDOWN_MS)
      ) {
        ability.lastFlip = now;
        applyFlip(fighter.composite, move, rng);
        return;
      }
      if (
        resolved.base === "brace" &&
        cooldownReady(ability.lastBrace, now, BRACE_COOLDOWN_MS) &&
        ability.braceUntil <= now
      ) {
        ability.lastBrace = now;
        ability.braceUntil = now + BRACE_DURATION_MS;
        ability.braceStiffness = activateBraceBurst(fighter.composite);
        return;
      }
      continue;
    }

    const cd = loadoutSlotAbilityCooldownMs(slotId);
    const sameAsLast = ability.lastSlot0Id === slotId;
    if (sameAsLast && !cooldownReady(ability.lastSlot0, now, cd)) continue;
    if (!sameAsLast && ability.lastSlot0Id && !cooldownReady(ability.lastSlot0, now, Math.min(cd, 800))) {
      // короткий глобальный анти-спам между разными кастами
      continue;
    }
    ability.lastSlot0 = now;
    ability.slot0Until = now + resolved.durationMs;
    ability.lastSlot0Id = slotId;
    applyLoadoutCastEffect(fighter.head, slotId, move);
    if (ABILITY_META[slotId]?.cat === "mobility") {
      ability.dashUntil = Math.max(
        ability.dashUntil,
        now + Math.min(500, resolved.durationMs),
      );
    }
    return;
  }
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
  const moveItemMult = fighter.loadoutMods?.moveMult ?? 1;

  fighter.braceActive = braceActive;
  fighter.moveSpeedMult =
    (ability.dashUntil > now ? DASH_SPEED_MULT : 1) * moveItemMult;

  if (braceActive) {
    stepBraceStance(composite);
  } else if (ability.braceStiffness) {
    restoreBraceStiffness(ability.braceStiffness);
    ability.braceStiffness = null;
  }

  // Гейтинг по лодауту: без loadout — классика; labUnlockBases — полный базовый набор.
  const unlock = Boolean(fighter.labUnlockBases) || !fighter.loadout;
  const canDash = unlock || loadoutAllowsAbility(fighter.loadout, "dash");
  const canFlip = unlock || loadoutAllowsAbility(fighter.loadout, "flip");
  const canBrace = unlock || loadoutAllowsAbility(fighter.loadout, "brace");

  if (
    input.dash &&
    canDash &&
    !resetActive &&
    cooldownReady(ability.lastDash, now, DASH_COOLDOWN_MS)
  ) {
    ability.lastDash = now;
    ability.dashUntil = now + DASH_DURATION_MS;
  }

  if (
    input.flip &&
    canFlip &&
    !resetActive &&
    cooldownReady(ability.lastFlip, now, FLIP_COOLDOWN_MS)
  ) {
    ability.lastFlip = now;
    applyFlip(composite, move, rng);
  }

  if (
    input.freeze &&
    canBrace &&
    !resetActive &&
    cooldownReady(ability.lastBrace, now, BRACE_COOLDOWN_MS) &&
    ability.braceUntil <= now
  ) {
    ability.lastBrace = now;
    ability.braceUntil = now + BRACE_DURATION_MS;
    ability.braceStiffness = activateBraceBurst(composite);
  }

  tryCastSlot0(fighter, ability, move, now, rng, resetActive);

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
  flags: {
    dash?: boolean;
    flip?: boolean;
    freeze?: boolean;
    reset?: boolean;
    dropWeapon?: boolean;
    abilitySlot?: boolean;
  },
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
    dropWeapon: flags.dropWeapon ?? false,
    abilitySlot: flags.abilitySlot ?? false,
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
  dropWeapon: false,
  abilitySlot: false,
});
