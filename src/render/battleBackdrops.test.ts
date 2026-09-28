import { describe, expect, it } from "vitest";
import {
  BATTLE_BACKDROP_IDS,
  buildBattleBackdropField,
  drawBattleBackdrop,
  pickBattleBackdrop,
  resetBattleBackdropCache,
} from "./battleBackdrops";

function mockCtx(): CanvasRenderingContext2D {
  const calls: string[] = [];
  return {
    save: () => calls.push("save"),
    restore: () => calls.push("restore"),
    fillRect: () => undefined,
    beginPath: () => undefined,
    arc: () => undefined,
    ellipse: () => undefined,
    fill: () => undefined,
    stroke: () => undefined,
    moveTo: () => undefined,
    lineTo: () => undefined,
    closePath: () => undefined,
    translate: () => undefined,
    scale: () => undefined,
    createLinearGradient: () => ({ addColorStop: () => undefined }),
    createRadialGradient: () => ({ addColorStop: () => undefined }),
    set fillStyle(_v: string) {},
    set strokeStyle(_v: string) {},
    set lineWidth(_v: number) {},
    set globalCompositeOperation(_v: string) {},
    _calls: calls,
  } as unknown as CanvasRenderingContext2D & { _calls: string[] };
}

describe("battleBackdrops", () => {
  it("has 10 backdrop themes", () => {
    expect(BATTLE_BACKDROP_IDS).toHaveLength(10);
  });

  it("pickBattleBackdrop maps rng buckets onto every catalog id", () => {
    const n = BATTLE_BACKDROP_IDS.length;
    for (let i = 0; i < n; i++) {
      expect(pickBattleBackdrop(() => (i + 0.5) / n)).toBe(BATTLE_BACKDROP_IDS[i]);
    }
  });

  it("builds distinct fields per theme", () => {
    resetBattleBackdropCache();
    const a = buildBattleBackdropField(800, 600, "orbital");
    const b = buildBattleBackdropField(800, 600, "ember_sun");
    expect(a.stars[0]).not.toEqual(b.stars[0]);
    expect(a.theme).toBe("orbital");
    expect(b.rocks.length).toBe(0);
    expect(buildBattleBackdropField(800, 600, "asteroid_belt").rocks.length).toBeGreaterThan(5);
  });

  it("paints every theme without throwing", () => {
    resetBattleBackdropCache();
    const ctx = mockCtx();
    for (const id of BATTLE_BACKDROP_IDS) {
      expect(() => drawBattleBackdrop(ctx, 640, 360, 12_000, id)).not.toThrow();
    }
  });
});
