import { describe, expect, it } from "vitest";
import {
  createHandGrabState,
  GRAB_REATTACH_COOLDOWN_MS,
} from "./types";
import {
  handGrabAttached,
  handGrabForcedRelease,
  handGrabKeyDown,
  handGrabKeyUp,
  isHandSeeking,
} from "./stateMachine";

describe("hand grab state machine", () => {
  it("keydown from idle enters seeking when off cooldown", () => {
    const hand = createHandGrabState();
    const next = handGrabKeyDown(hand, 1000);
    expect(next.phase).toBe("seeking");
  });

  it("keydown respects cooldown", () => {
    const hand = { ...createHandGrabState(), cooldownUntil: 2000 };
    const next = handGrabKeyDown(hand, 1000);
    expect(next.phase).toBe("idle");
  });

  it("keyup from seeking returns idle", () => {
    const hand = { ...createHandGrabState(), phase: "seeking" as const };
    const next = handGrabKeyUp(hand);
    expect(next.phase).toBe("idle");
  });

  it("attach only from seeking", () => {
    const hand = { ...createHandGrabState(), phase: "seeking" as const };
    const next = handGrabAttached(hand, {
      bodyId: 1,
      kind: "wall",
    });
    expect(next.phase).toBe("attached");
    expect(next.target?.bodyId).toBe(1);
  });

  it("forced release sets cooldown", () => {
    const hand = {
      ...createHandGrabState(),
      phase: "attached" as const,
      target: { bodyId: 2, kind: "fighter" as const },
    };
    const now = 5000;
    const next = handGrabForcedRelease(hand, now);
    expect(next.phase).toBe("idle");
    expect(next.cooldownUntil).toBe(now + GRAB_REATTACH_COOLDOWN_MS);
  });

  it("isHandSeeking checks phase and cooldown", () => {
    const hand = { ...createHandGrabState(), phase: "seeking" as const };
    expect(isHandSeeking(hand, 0)).toBe(true);
    expect(isHandSeeking(hand, 9999)).toBe(true);
  });
});
