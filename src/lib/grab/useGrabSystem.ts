import { keyEventMatches } from "@/input/keyBindings";
import { GRAB_ENABLED } from "@/lib/battleTuning";
import { useSettings, type AbilityBindings } from "@/settings/SettingsContext";
import { useEventCollisionStart } from "@1.framework/matter4react";
import Matter, {
  type Body,
  type Composite,
  type Engine,
} from "matter-js";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type MutableRefObject,
  type RefObject,
} from "react";
import { tagItemOwner } from "@/items/buildItem";
import {
  buildCompositeBodyMap,
  createGrabPin,
  dampGrabBodies,
  grabAttachClosingSpeed,
  MAX_GRAB_ATTACH_CLOSING,
  removeGrabConstraints,
  resolveGrabTarget,
} from "./attach";
import { getHandBody, isHandBody, tagStickmanHands } from "./hands";
import {
  createGrabHitTracker,
  recordGrabVictimHit,
  shouldForceReleaseGrabber,
} from "./rules";
import {
  handGrabAttached,
  handGrabForcedRelease,
  handGrabKeyDown,
  handGrabKeyUp,
  isHandSeeking,
} from "./stateMachine";
import {
  createFighterGrabState,
  type FighterGrabState,
  type GrabVisualLine,
  type HandSide,
} from "./types";

export interface GrabSystemView {
  grabRef: MutableRefObject<FighterGrabState>;
  linesRef: MutableRefObject<GrabVisualLine[]>;
  leftHeldRef: MutableRefObject<boolean>;
  rightHeldRef: MutableRefObject<boolean>;
  releaseHand: (side: HandSide, forced?: boolean) => void;
}

const victimHitTrackers = new Map<string, ReturnType<typeof createGrabHitTracker>>();

export function useGrabSystem(opts: {
  fighterId: string;
  playerCompositeRef: MutableRefObject<Composite | undefined>;
  allComposites: Composite[];
  itemCompositesRef?: RefObject<Composite[]>;
  disabledRef?: MutableRefObject<boolean>;
  /** Если false — клавиатура не слушается (удалённый боец на хосте). */
  keyboardInput?: boolean;
  /** Внешние ref удержания Q/E (сеть). */
  externalHeldRefs?: {
    left: RefObject<boolean>;
    right: RefObject<boolean>;
  };
  /** Переопределение клавиш хвата (второй локальный игрок). */
  abilityBindings?: AbilityBindings;
  /** Физику хвата считает BattleSession — только ввод/ref. */
  skipSimulation?: boolean;
}): GrabSystemView {
  const { settings } = useSettings();
  const abilities = opts.abilityBindings ?? settings.abilities;

  const grabRef = useRef<FighterGrabState>(
    createFighterGrabState(opts.fighterId),
  );
  const [, bump] = useState(0);
  const sync = useCallback(() => bump((n) => n + 1), []);

  // Composite id жертвы меняется каждый рематч — без чистки Map с трекерами
  // ударов растёт бесконечно между боями.
  useEffect(() => {
    const prefix = `${opts.fighterId}:`;
    for (const key of victimHitTrackers.keys()) {
      if (key.startsWith(prefix)) victimHitTrackers.delete(key);
    }
  }, [opts.fighterId, opts.playerCompositeRef.current?.id]);

  const leftHeldRef = useRef(false);
  const rightHeldRef = useRef(false);
  const linesRef = useRef<GrabVisualLine[]>([]);
  const engineRef = useRef<Engine | null>(null);

  const releaseHand = useCallback(
    (side: HandSide, forced = false) => {
      const engine = engineRef.current;
      const now = performance.now();
      const handState =
        side === "left" ? grabRef.current.left : grabRef.current.right;
      if (engine) removeGrabConstraints(engine, handState.constraints);

      const released = forced
        ? handGrabForcedRelease(handState, now)
        : handGrabKeyUp(handState);
      if (side === "left") grabRef.current = { ...grabRef.current, left: released };
      else grabRef.current = { ...grabRef.current, right: released };
      sync();
    },
    [sync],
  );

  const attachHand = useCallback(
    (
      side: HandSide,
      handBody: Body,
      targetBody: Body,
      target: NonNullable<FighterGrabState["left"]["target"]>,
      engine: Engine,
      contactPoint?: Matter.Vector,
    ) => {
      const constraints = createGrabPin(
        engine,
        handBody,
        targetBody,
        target.kind,
        contactPoint,
      );
      dampGrabBodies(handBody, targetBody.isStatic ? null : targetBody);
      const hand = side === "left" ? grabRef.current.left : grabRef.current.right;
      const attached = {
        ...handGrabAttached(hand, target, performance.now()),
        constraints,
      };
      if (side === "left") {
        grabRef.current = { ...grabRef.current, left: attached };
      } else {
        grabRef.current = { ...grabRef.current, right: attached };
      }
      if (target.kind === "grip" || target.kind === "item") {
        const itemComposite = opts.itemCompositesRef?.current?.find((c) =>
          c.bodies.some((b) => b.id === target.bodyId),
        );
        if (itemComposite) tagItemOwner(itemComposite, opts.fighterId);
      }
      sync();
    },
    [sync],
  );

  useEffect(() => {
    const composite = opts.playerCompositeRef.current;
    if (composite) tagStickmanHands(composite, opts.fighterId);
  }, [opts.fighterId, opts.playerCompositeRef]);

  useEffect(() => {
    if (!GRAB_ENABLED || opts.keyboardInput === false) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (opts.disabledRef?.current) return;
      const now = performance.now();
      if (keyEventMatches(abilities.grabL, e)) {
        e.preventDefault();
        leftHeldRef.current = true;
        grabRef.current = {
          ...grabRef.current,
          left: handGrabKeyDown(grabRef.current.left, now),
        };
        sync();
      }
      if (keyEventMatches(abilities.grabR, e)) {
        e.preventDefault();
        rightHeldRef.current = true;
        grabRef.current = {
          ...grabRef.current,
          right: handGrabKeyDown(grabRef.current.right, now),
        };
        sync();
      }
    };

    const onKeyUp = (e: KeyboardEvent) => {
      if (keyEventMatches(abilities.grabL, e)) {
        leftHeldRef.current = false;
        releaseHand("left");
      }
      if (keyEventMatches(abilities.grabR, e)) {
        rightHeldRef.current = false;
        releaseHand("right");
      }
    };

    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
    };
  }, [abilities.grabL, abilities.grabR, opts.disabledRef, opts.keyboardInput, releaseHand, sync]);

  useEffect(() => {
    if (!GRAB_ENABLED) return;
    const ext = opts.externalHeldRefs;
    if (!ext) return;
    let raf = 0;
    const tick = () => {
      if (opts.disabledRef?.current) {
        raf = requestAnimationFrame(tick);
        return;
      }
      const now = performance.now();
      for (const side of ["left", "right"] as const) {
        const heldRef = side === "left" ? ext.left : ext.right;
        const held = heldRef.current;
        const prevHeld = side === "left" ? leftHeldRef.current : rightHeldRef.current;
        if (held && !prevHeld) {
          if (side === "left") leftHeldRef.current = true;
          else rightHeldRef.current = true;
          const handState =
            side === "left" ? grabRef.current.left : grabRef.current.right;
          const next = handGrabKeyDown(handState, now);
          if (side === "left") grabRef.current = { ...grabRef.current, left: next };
          else grabRef.current = { ...grabRef.current, right: next };
          sync();
        } else if (!held && prevHeld) {
          if (side === "left") leftHeldRef.current = false;
          else rightHeldRef.current = false;
          releaseHand(side);
        }
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [opts.externalHeldRefs, opts.disabledRef, releaseHand, sync]);

  useEventCollisionStart((event) => {
    if (!GRAB_ENABLED || opts.skipSimulation) return;
    engineRef.current = event.source;
    const now = performance.now();
    const compositeMap = buildCompositeBodyMap(opts.allComposites);

    for (const pair of event.pairs) {
      const { bodyA, bodyB, collision } = pair;
      const contact = collision.supports[0];
      for (const [handBody, otherBody] of [
        [bodyA, bodyB] as const,
        [bodyB, bodyA] as const,
      ]) {
        if (!isHandBody(handBody)) continue;
        if (grabPluginLocal(handBody).fighterId !== opts.fighterId) continue;

        const side: HandSide =
          grabPluginLocal(handBody).part === "handR" ? "right" : "left";
        const held =
          side === "left" ? leftHeldRef.current : rightHeldRef.current;
        const handState =
          side === "left" ? grabRef.current.left : grabRef.current.right;
        if (!held || !isHandSeeking(handState, now)) continue;
        if (handState.phase === "attached") continue;

        const target = resolveGrabTarget(handBody, otherBody, compositeMap);
        if (!target) continue;

        if (grabAttachClosingSpeed(handBody, otherBody) > MAX_GRAB_ATTACH_CLOSING) {
          continue;
        }

        attachHand(
          side,
          handBody,
          otherBody,
          target,
          event.source,
          contact ? { x: contact.x, y: contact.y } : undefined,
        );
      }
    }
  }, [opts.allComposites, opts.fighterId, attachHand]);

  useEffect(() => {
    let raf = 0;
    const tick = () => {
      const composite = opts.playerCompositeRef.current;
      const lines: GrabVisualLine[] = [];
      if (composite && engineRef.current) {
        const allBodies = Matter.Composite.allBodies(engineRef.current.world);
        for (const side of ["left", "right"] as const) {
          const hand = side === "left" ? grabRef.current.left : grabRef.current.right;
          if (hand.phase !== "attached" || !hand.target) continue;
          const handBody = getHandBody(composite, side);
          const target = allBodies.find((b) => b.id === hand.target!.bodyId);
          if (!handBody || !target) continue;
          lines.push({
            from: { x: handBody.position.x, y: handBody.position.y },
            to: { x: target.position.x, y: target.position.y },
            hand: side,
            color: "#fbbf24",
          });
        }
      }
      linesRef.current = lines;
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [opts.playerCompositeRef]);

  return {
    grabRef,
    linesRef,
    leftHeldRef,
    rightHeldRef,
    releaseHand,
  };
}

function grabPluginLocal(body: Body) {
  return (body.plugin ?? {}) as { fighterId?: string; part?: string };
}

/** Вызывается из useHealth когда жертва бьёт держателя. */
export function notifyGrabVictimHit(
  grabRef: RefObject<FighterGrabState>,
  victimCompositeId: number,
  releaseHand: (side: HandSide, forced?: boolean) => void,
): void {
  const grab = grabRef.current;
  if (!grab) return;
  const key = `${grab.fighterId}:${victimCompositeId}`;
  let tracker = victimHitTrackers.get(key);
  if (!tracker) {
    tracker = createGrabHitTracker();
    victimHitTrackers.set(key, tracker);
  }
  const now = performance.now();
  if (!recordGrabVictimHit(tracker, now)) return;
  const sides = shouldForceReleaseGrabber(grab, victimCompositeId);
  for (const side of sides) releaseHand(side, true);
  victimHitTrackers.delete(key);
}

export type { FighterGrabState, GrabVisualLine, HandSide };
