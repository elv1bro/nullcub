import { describe, expect, it } from "vitest";
import {
  BLOODY_MAX_ALIVE,
  particleCountForImpact,
  particleCountForReplayDamage,
  spawnBloodyParticles,
} from "./bloodyParticles";
import { Engine } from "matter-js";

describe("bloodyParticles counts", () => {
  it("clamps live impact counts", () => {
    expect(particleCountForImpact(1, 0.1)).toBe(6);
    expect(particleCountForImpact(200, 50)).toBe(28);
  });

  it("scales replay debris with damage", () => {
    expect(particleCountForReplayDamage(5)).toBeGreaterThanOrEqual(8);
    expect(particleCountForReplayDamage(100)).toBeLessThanOrEqual(24);
    expect(particleCountForReplayDamage(40)).toBeGreaterThan(
      particleCountForReplayDamage(10),
    );
  });

  it("respects alive budget so series cannot pile past the cap", () => {
    const engine = Engine.create();
    const nearCap = spawnBloodyParticles(engine.world, 0, 0, "#f00", {
      count: 28,
      alive: BLOODY_MAX_ALIVE - 4,
    });
    expect(nearCap.length).toBe(4);

    const full = spawnBloodyParticles(engine.world, 0, 0, "#0f0", {
      count: 20,
      alive: BLOODY_MAX_ALIVE,
    });
    expect(full).toEqual([]);
  });
});
