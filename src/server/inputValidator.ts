import { emptyInput } from "@/core/abilityTick";
import type { NetInputPayload } from "@/net/protocol";

const MAX_MOVE = 1.05;
const MAX_INPUTS_PER_SEC = 45;

function clampAxis(value: unknown): number {
  const n = typeof value === "number" && Number.isFinite(value) ? value : 0;
  return Math.max(-MAX_MOVE, Math.min(MAX_MOVE, n));
}

/** Безопасный clamp: битый/пустой payload → emptyInput, без throw. */
export function clampMove(input: unknown): NetInputPayload {
  if (!input || typeof input !== "object") return emptyInput();
  const raw = input as Partial<NetInputPayload> & {
    move?: { x?: unknown; y?: unknown };
  };
  const move = raw.move && typeof raw.move === "object" ? raw.move : {};
  return {
    seq: typeof raw.seq === "number" && Number.isFinite(raw.seq) ? raw.seq : 0,
    t: typeof raw.t === "number" && Number.isFinite(raw.t) ? raw.t : 0,
    move: { x: clampAxis(move.x), y: clampAxis(move.y) },
    dash: Boolean(raw.dash),
    flip: Boolean(raw.flip),
    freeze: Boolean(raw.freeze),
    reset: Boolean(raw.reset),
    grabL: Boolean(raw.grabL),
    grabR: Boolean(raw.grabR),
  };
}

export class InputRateLimiter {
  private lastAt = 0;
  private count = 0;
  private windowStart = 0;

  accept(now: number): boolean {
    if (now - this.windowStart > 1000) {
      this.windowStart = now;
      this.count = 0;
    }
    this.count++;
    if (this.count > MAX_INPUTS_PER_SEC) return false;
    if (now - this.lastAt < 1000 / MAX_INPUTS_PER_SEC - 2) return false;
    this.lastAt = now;
    return true;
  }
}
