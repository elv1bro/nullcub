import { keyEventMatches } from "@/input/keyBindings";
import { useMovementVectorRef } from "@/input/movementKeys";
import { pollGamepadAbilityEdges } from "@/input/gamepad";
import { cooldownRemaining } from "@/core/abilityTick";
import type { AbilityBindings, ControlBindings } from "@/settings/SettingsContext";
import { useSettings } from "@/settings/SettingsContext";
import Matter, { Body, Composite, Vector, type IEventTimestamped } from "matter-js";
import { useEventBeforeUpdate } from "@1.framework/matter4react";
import { useEffect, useRef, useState, type MutableRefObject } from "react";
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
} from "./battleTuning";
import {
  activateBraceBurst,
  restoreBraceStiffness,
  stepBraceStance,
} from "./braceStance";
import {
  type PoseSnapshot,
  stepPoseReset,
} from "./ragdollPoseReset";

export type AbilityCooldownView = {
  dashRemainingMs: number;
  dashActiveRemainingMs: number;
  flipRemainingMs: number;
  freezeRemainingMs: number;
  freezeActiveRemainingMs: number;
  resetRemainingMs: number;
  dashReady: boolean;
  flipReady: boolean;
  freezeReady: boolean;
  resetReady: boolean;
  lastDashFlash: number;
  lastFlipFlash: number;
  lastFreezeFlash: number;
  lastResetFlash: number;
  moveSpeedMultRef: MutableRefObject<number>;
  inputBlockedRef: MutableRefObject<boolean>;
  braceActiveRef: MutableRefObject<boolean>;
};

function applyFlip(composite: Composite, move: Vector): void {
  let sign = Math.random() > 0.5 ? 1 : -1;
  if (Math.abs(move.x) > 0.1) sign = move.x > 0 ? 1 : -1;
  else if (Math.abs(move.y) > 0.1) sign = move.y > 0 ? -1 : 1;

  for (const body of composite.bodies) {
    const wobble = 0.92 + Math.random() * 0.16;
    Body.setAngularVelocity(body, sign * FLIP_ANGULAR_VEL * wobble);
  }
}

export function usePlayerAbilities(
  headRef: MutableRefObject<Body | undefined>,
  compositeRef: MutableRefObject<Composite | undefined>,
  poseSnapRef: MutableRefObject<PoseSnapshot | null>,
  disabledRef?: MutableRefObject<boolean>,
  options?: {
    enabled?: boolean;
    abilities?: AbilityBindings;
    controls?: ControlBindings;
    /** Только UI кулдаунов — физику считает BattleSession. */
    skipPhysics?: boolean;
    abilityFlagsOut?: MutableRefObject<{
      dash: boolean;
      flip: boolean;
      freeze: boolean;
      reset: boolean;
      dropWeapon: boolean;
      abilitySlot: boolean;
    }>;
    /** Индекс геймпада (0 = первый). null/undefined = только клавиатура. */
    gamepadIndex?: number | null;
  },
): AbilityCooldownView {
  const { settings } = useSettings();
  const active = options?.enabled !== false;
  const abilities = options?.abilities ?? settings.abilities;
  const controls = options?.controls ?? settings.controls;
  const gamepadIndex = options?.gamepadIndex ?? null;
  const readMovement = useMovementVectorRef(controls, {
    includeArrows: false,
    gamepadIndex,
  });
  const gamepadBtnPrevRef = useRef<boolean[]>([]);

  const dropWeaponQueuedRef = useRef(false);
  const abilitySlotQueuedRef = useRef(false);
  const lastDashRef = useRef(0);
  const dashActiveUntilRef = useRef(0);
  const lastFlipRef = useRef(0);
  const lastBraceRef = useRef(0);
  const braceUntilRef = useRef(0);
  const braceStiffnessRef = useRef<
    ReturnType<typeof activateBraceBurst> | null
  >(null);
  const lastResetRef = useRef(0);
  const resetUntilRef = useRef(0);
  const resetStartRef = useRef(0);

  const dashQueuedRef = useRef(false);
  const flipQueuedRef = useRef(false);
  const freezeQueuedRef = useRef(false);
  const resetQueuedRef = useRef(false);
  const dashFlashRef = useRef(0);
  const flipFlashRef = useRef(0);
  const freezeFlashRef = useRef(0);
  const resetFlashRef = useRef(0);
  const moveSpeedMultRef = useRef(1);
  const inputBlockedRef = useRef(false);
  const braceActiveRef = useRef(false);

  const [view, setView] = useState<
    Omit<
      AbilityCooldownView,
      "moveSpeedMultRef" | "inputBlockedRef" | "braceActiveRef"
    >
  >({
    dashRemainingMs: 0,
    dashActiveRemainingMs: 0,
    flipRemainingMs: 0,
    freezeRemainingMs: 0,
    freezeActiveRemainingMs: 0,
    resetRemainingMs: 0,
    dashReady: true,
    flipReady: true,
    freezeReady: true,
    resetReady: true,
    lastDashFlash: 0,
    lastFlipFlash: 0,
    lastFreezeFlash: 0,
    lastResetFlash: 0,
  });

  useEffect(() => {
    if (!active) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.repeat) return;
      if (disabledRef?.current) return;
      if (keyEventMatches(abilities.dash, e)) {
        e.preventDefault();
        dashQueuedRef.current = true;
      }
      if (keyEventMatches(abilities.flip, e)) {
        e.preventDefault();
        flipQueuedRef.current = true;
      }
      if (keyEventMatches(abilities.freeze, e)) {
        e.preventDefault();
        freezeQueuedRef.current = true;
      }
      if (keyEventMatches(abilities.reset, e)) {
        e.preventDefault();
        resetQueuedRef.current = true;
      }
      if (keyEventMatches(abilities.dropWeapon, e)) {
        e.preventDefault();
        dropWeaponQueuedRef.current = true;
      }
      if (keyEventMatches(abilities.slot4, e)) {
        e.preventDefault();
        abilitySlotQueuedRef.current = true;
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [active, disabledRef, abilities]);

  useEffect(() => {
    if (!active) return;
    let frame = 0;
    let lastViewAt = 0;
    const VIEW_HZ = 12;
    const tick = () => {
      const now = performance.now();
      const dashRemaining = cooldownRemaining(lastDashRef.current, now, DASH_COOLDOWN_MS);
      const dashActiveRemaining = Math.max(0, dashActiveUntilRef.current - now);
      const flipRemaining = cooldownRemaining(lastFlipRef.current, now, FLIP_COOLDOWN_MS);
      const freezeRemaining = cooldownRemaining(lastBraceRef.current, now, BRACE_COOLDOWN_MS);
      const freezeActiveRemaining = Math.max(0, braceUntilRef.current - now);
      const resetRemaining = cooldownRemaining(lastResetRef.current, now, RESET_COOLDOWN_MS);

      moveSpeedMultRef.current =
        dashActiveRemaining > 0 ? DASH_SPEED_MULT : 1;

      inputBlockedRef.current = resetUntilRef.current > now;
      braceActiveRef.current = freezeActiveRemaining > 0;

      if (now - lastViewAt >= 1000 / VIEW_HZ) {
        lastViewAt = now;
        setView({
          dashRemainingMs: dashRemaining,
          dashActiveRemainingMs: dashActiveRemaining,
          flipRemainingMs: flipRemaining,
          freezeRemainingMs: freezeRemaining,
          freezeActiveRemainingMs: freezeActiveRemaining,
          resetRemainingMs: resetRemaining,
          dashReady: dashRemaining <= 0,
          flipReady: flipRemaining <= 0,
          freezeReady: freezeRemaining <= 0,
          resetReady: resetRemaining <= 0,
          lastDashFlash: dashFlashRef.current,
          lastFlipFlash: flipFlashRef.current,
          lastFreezeFlash: freezeFlashRef.current,
          lastResetFlash: resetFlashRef.current,
        });
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [active]);

  /** Server-authoritative: кулдауны локально, флаги — на сервер по INPUT_HZ. */
  useEffect(() => {
    if (!active || !options?.skipPhysics || !options.abilityFlagsOut) return;
    const flush = () => {
      const now = performance.now();
      const resetActive = resetUntilRef.current > now;
      if (gamepadIndex != null) {
        const edges = pollGamepadAbilityEdges(
          gamepadBtnPrevRef.current,
          gamepadIndex,
        );
        if (edges.dash) dashQueuedRef.current = true;
        if (edges.flip) flipQueuedRef.current = true;
        if (edges.freeze) freezeQueuedRef.current = true;
        if (edges.reset) resetQueuedRef.current = true;
      }

      let dash = false;
      let flip = false;
      let dropWeapon = false;
      let abilitySlot = false;
      let freeze = false;
      let reset = false;

      if (dashQueuedRef.current) {
        dashQueuedRef.current = false;
        if (!resetActive && (lastDashRef.current === 0 || now - lastDashRef.current >= DASH_COOLDOWN_MS)) {
          lastDashRef.current = now;
          dashActiveUntilRef.current = now + DASH_DURATION_MS;
          dashFlashRef.current = now;
          dash = true;
        }
      }

      if (flipQueuedRef.current) {
        flipQueuedRef.current = false;
        if (!resetActive && (lastFlipRef.current === 0 || now - lastFlipRef.current >= FLIP_COOLDOWN_MS)) {
          lastFlipRef.current = now;
          flipFlashRef.current = now;
          flip = true;
        }
      }

      if (freezeQueuedRef.current) {
        freezeQueuedRef.current = false;
        if (
          !resetActive &&
          (lastBraceRef.current === 0 ||
            now - lastBraceRef.current >= BRACE_COOLDOWN_MS) &&
          braceUntilRef.current <= now
        ) {
          lastBraceRef.current = now;
          braceUntilRef.current = now + BRACE_DURATION_MS;
          freezeFlashRef.current = now;
          freeze = true;
        }
      }

      if (resetQueuedRef.current) {
        resetQueuedRef.current = false;
        if (
          poseSnapRef.current &&
          !resetActive &&
          (lastResetRef.current === 0 ||
            now - lastResetRef.current >= RESET_COOLDOWN_MS) &&
          resetUntilRef.current <= now
        ) {
          braceUntilRef.current = 0;
          lastResetRef.current = now;
          resetStartRef.current = now;
          resetUntilRef.current = now + RESET_DURATION_MS;
          resetFlashRef.current = now;
          reset = true;
        }
      }

      if (dropWeaponQueuedRef.current) {
        dropWeaponQueuedRef.current = false;
        dropWeapon = true;
      }
      if (abilitySlotQueuedRef.current) {
        abilitySlotQueuedRef.current = false;
        abilitySlot = true;
      }

      // Sticky until useCoreInputBridge / DedicatedBattleView consume (one-shot).
      options.abilityFlagsOut!.current.dash ||= dash;
      options.abilityFlagsOut!.current.flip ||= flip;
      options.abilityFlagsOut!.current.freeze ||= freeze;
      options.abilityFlagsOut!.current.reset ||= reset;
      options.abilityFlagsOut!.current.dropWeapon ||= dropWeapon;
      options.abilityFlagsOut!.current.abilitySlot ||= abilitySlot;
    };
    // Сразу + каждый кадр: без 30Hz задержки dash/flip после keydown.
    flush();
    let raf = 0;
    const tick = () => {
      flush();
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [
    active,
    options?.skipPhysics,
    options?.abilityFlagsOut,
    poseSnapRef,
    gamepadIndex,
  ]);

  useEventBeforeUpdate(
    (_event: IEventTimestamped<Matter.Engine>) => {
      if (!active || options?.skipPhysics) return;
      const head = headRef.current;
      const composite = compositeRef.current;
      if (!(head && composite)) return;

      const now = performance.now();
      if (gamepadIndex != null) {
        const edges = pollGamepadAbilityEdges(
          gamepadBtnPrevRef.current,
          gamepadIndex,
        );
        if (edges.dash) dashQueuedRef.current = true;
        if (edges.flip) flipQueuedRef.current = true;
        if (edges.freeze) freezeQueuedRef.current = true;
        if (edges.reset) resetQueuedRef.current = true;
      }
      const move = readMovement();
      const braceActive = braceUntilRef.current > now;
      braceActiveRef.current = braceActive;
      const resetActive = resetUntilRef.current > now;

      if (braceActive) {
        stepBraceStance(composite);
      } else if (braceStiffnessRef.current) {
        restoreBraceStiffness(braceStiffnessRef.current);
        braceStiffnessRef.current = null;
      }

      if (resetActive && poseSnapRef.current) {
        const progress = (now - resetStartRef.current) / RESET_DURATION_MS;
        stepPoseReset(composite, poseSnapRef.current, progress);
      }

      if (dashQueuedRef.current) {
        dashQueuedRef.current = false;
        if (!resetActive && (lastDashRef.current === 0 || now - lastDashRef.current >= DASH_COOLDOWN_MS)) {
          lastDashRef.current = now;
          dashActiveUntilRef.current = now + DASH_DURATION_MS;
          dashFlashRef.current = now;
        }
      }

      if (flipQueuedRef.current) {
        flipQueuedRef.current = false;
        if (!resetActive && (lastFlipRef.current === 0 || now - lastFlipRef.current >= FLIP_COOLDOWN_MS)) {
          lastFlipRef.current = now;
          flipFlashRef.current = now;
          applyFlip(composite, move);
        }
      }

      if (freezeQueuedRef.current) {
        freezeQueuedRef.current = false;
        if (
          !resetActive &&
          (lastBraceRef.current === 0 ||
            now - lastBraceRef.current >= BRACE_COOLDOWN_MS) &&
          braceUntilRef.current <= now
        ) {
          lastBraceRef.current = now;
          braceUntilRef.current = now + BRACE_DURATION_MS;
          braceStiffnessRef.current = activateBraceBurst(composite);
          freezeFlashRef.current = now;
        }
      }

      if (resetQueuedRef.current) {
        resetQueuedRef.current = false;
        if (
          poseSnapRef.current &&
          (lastResetRef.current === 0 ||
            now - lastResetRef.current >= RESET_COOLDOWN_MS) &&
          resetUntilRef.current <= now
        ) {
          braceUntilRef.current = 0;
          if (braceStiffnessRef.current) {
            restoreBraceStiffness(braceStiffnessRef.current);
            braceStiffnessRef.current = null;
          }
          lastResetRef.current = now;
          resetStartRef.current = now;
          resetUntilRef.current = now + RESET_DURATION_MS;
          resetFlashRef.current = now;
        }
      }
    },
    [
      active,
      headRef,
      compositeRef,
      poseSnapRef,
      disabledRef,
      readMovement,
    ],
  );

  return { ...view, moveSpeedMultRef, inputBlockedRef, braceActiveRef };
}
