import {
  createHandGrabState,
  type GrabPhase,
  type HandGrabState,
  type HandSide,
} from "./types";

/** Переходы стейт-машины одной руки (чистая логика для тестов). */
export function handGrabKeyDown(
  hand: HandGrabState,
  now: number,
): HandGrabState {
  if (hand.phase === "attached") return hand;
  if (now < hand.cooldownUntil) return hand;
  if (hand.phase === "seeking") return hand;
  return { ...hand, phase: "seeking" };
}

export function handGrabKeyUp(hand: HandGrabState): HandGrabState {
  if (hand.phase === "idle") return hand;
  return {
    ...createHandGrabState(),
    cooldownUntil: hand.cooldownUntil,
  };
}

export function handGrabAttached(
  hand: HandGrabState,
  target: NonNullable<HandGrabState["target"]>,
  now = performance.now(),
): HandGrabState {
  if (hand.phase !== "seeking") return hand;
  return {
    ...hand,
    phase: "attached",
    target,
    attachedAt: now,
  };
}

export function handGrabForcedRelease(
  hand: HandGrabState,
  now: number,
): HandGrabState {
  if (hand.phase !== "attached") return hand;
  return {
    ...createHandGrabState(),
    cooldownUntil: now + 500,
  };
}

export function isHandSeeking(hand: HandGrabState, now: number): boolean {
  return hand.phase === "seeking" && now >= hand.cooldownUntil;
}

export function isHandAttached(hand: HandGrabState): boolean {
  return hand.phase === "attached";
}

export function handSideFromPart(part: string | undefined): HandSide | null {
  if (part === "handL") return "left";
  if (part === "handR") return "right";
  return null;
}

export function nextPhaseAfterRelease(_from: GrabPhase): GrabPhase {
  return "idle";
}
