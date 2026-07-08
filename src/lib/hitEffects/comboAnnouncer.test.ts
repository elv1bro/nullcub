import { describe, expect, it } from "vitest";
import { createHitEffectStore, HEAVY_DAMAGE } from "./store";
import { comboLabel, updateCombo } from "./comboAnnouncer";
import { dispatchHitEffects } from "./dispatch";

describe("comboAnnouncer", () => {
  it("stacks combo within window", () => {
    const store = createHitEffectStore();
    const t0 = 1000;
    expect(updateCombo(store, "player", t0)).toBe(1);
    expect(updateCombo(store, "player", t0 + 400)).toBe(2);
    expect(updateCombo(store, "player", t0 + 800)).toBe(3);
    expect(comboLabel(3, "ru")).toBe("×3 КОМБО!");
  });

  it("resets combo for other side", () => {
    const store = createHitEffectStore();
    updateCombo(store, "player", 1000);
    updateCombo(store, "player", 1200);
    expect(updateCombo(store, "opponent", 1300)).toBe(1);
  });
});

describe("dispatchHitEffects", () => {
  it("schedules hit-stop and slow-mo on heavy hits", () => {
    const store = createHitEffectStore();
    dispatchHitEffects(store, {
      damage: HEAVY_DAMAGE + 5,
      contactX: 500,
      contactY: 900,
      aggressorSide: "player",
      aggressorColor: "#fff",
      aggressorColors: { main: "#fff", secondary: "#ccc" },
      arenaHeight: 1000,
      language: "en",
      slot: 0,
      now: 5000,
    });
    expect(store.timeSegments.length).toBeGreaterThanOrEqual(2);
    expect(store.timeSegments[0]?.scale).toBe(0);
    expect(store.shake.intensity).toBeGreaterThan(0);
    expect(store.flash).not.toBeNull();
  });

  it("spawns shockwave near floor", () => {
    const store = createHitEffectStore();
    dispatchHitEffects(store, {
      damage: 20,
      contactX: 400,
      contactY: 850,
      aggressorSide: "opponent",
      aggressorColor: "#f00",
      aggressorColors: { main: "#f00", secondary: "#900" },
      arenaHeight: 1000,
      language: "ru",
      slot: 1,
      now: 2000,
    });
    expect(store.shockwaves.length).toBe(1);
  });
});
