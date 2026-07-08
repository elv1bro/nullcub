import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Регрессия dual-path: LeveL1 всегда гоняет BattleSession и глушит
 * legacy collision damage в useHealth.
 */
describe("LeveL1 coreSim contract", () => {
  const src = readFileSync(
    resolve(__dirname, "LeveL1.tsx"),
    "utf8",
  );

  it("hardcodes coreSim = true", () => {
    expect(src).toMatch(/const\s+coreSim\s*=\s*true/);
  });

  it("passes skipCollisions when coreSim", () => {
    expect(src).toMatch(/skipCollisions:\s*true/);
  });

  it("syncs HP from core session on hit", () => {
    expect(src).toMatch(/syncHpFromCore/);
    expect(src).toMatch(/reportCoreHit/);
  });
});
