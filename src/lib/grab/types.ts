import type { Body, Constraint } from "matter-js";

export type HandSide = "left" | "right";

export type GrabPhase = "idle" | "seeking" | "attached";

export interface GrabTargetRef {
  bodyId: number;
  compositeId?: number;
  kind: "fighter" | "wall" | "item" | "grip";
}

export interface HandGrabState {
  phase: GrabPhase;
  constraints: Constraint[];
  target: GrabTargetRef | null;
  /** Не искать новый захват до этого времени (forced release). */
  cooldownUntil: number;
  /** performance.now() — короткая неуязвимость от constraint-удара. */
  attachedAt: number;
}

export function createHandGrabState(): HandGrabState {
  return {
    phase: "idle",
    constraints: [],
    target: null,
    cooldownUntil: 0,
    attachedAt: 0,
  };
}

export interface FighterGrabState {
  fighterId: string;
  left: HandGrabState;
  right: HandGrabState;
}

export function createFighterGrabState(fighterId: string): FighterGrabState {
  return {
    fighterId,
    left: createHandGrabState(),
    right: createHandGrabState(),
  };
}

export interface GrabVisualLine {
  from: { x: number; y: number };
  to: { x: number; y: number };
  hand: HandSide;
  color: string;
}

export const GRAB_REATTACH_COOLDOWN_MS = 500;
export const GRAB_ATTACH_DAMAGE_GRACE_MS = 350;
export const GRAB_FORCED_RELEASE_HITS = 2;
export const GRAB_FORCED_RELEASE_WINDOW_MS = 1000;

export type GrabBodyPlugin = {
  part?: "handL" | "handR";
  fighterId?: string;
  gripOf?: string;
  itemId?: string;
  ownerFighterId?: string;
};

export function grabPlugin(body: Body): GrabBodyPlugin {
  return (body.plugin ?? {}) as GrabBodyPlugin;
}
