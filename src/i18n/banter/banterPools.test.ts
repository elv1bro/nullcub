import { describe, expect, it } from "vitest";
import {
  BANTER_POOL_SIZE,
  banterPools,
  pickBanterLine,
  shouldSpawnBanter,
} from "@/i18n/banter";
import { cyrillicRatio } from "@/i18n/banter/buildPool";
import { BANTER_SPAWN_CHANCE } from "@/lib/banterConfig";

function avgCyrillicRatio(lines: string[]): number {
  if (lines.length === 0) return 0;
  return lines.reduce((a, l) => a + cyrillicRatio(l), 0) / lines.length;
}

describe("banter pools", () => {
  for (const lang of ["en", "ru"] as const) {
    it(`builds ~${BANTER_POOL_SIZE} lines per side (${lang})`, () => {
      const { safe, spicy } = banterPools[lang];
      expect(safe.player.length).toBe(BANTER_POOL_SIZE);
      expect(safe.opponent.length).toBe(BANTER_POOL_SIZE);
      expect(spicy.player.length).toBe(BANTER_POOL_SIZE);
      expect(spicy.opponent.length).toBe(BANTER_POOL_SIZE);
    });
  }

  it("ru pools are predominantly Russian (not English memes)", () => {
    const samples = [
      ...banterPools.ru.safe.player.slice(0, 80),
      ...banterPools.ru.safe.opponent.slice(0, 80),
      ...banterPools.ru.spicy.player.slice(0, 40),
      ...banterPools.ru.spicy.opponent.slice(0, 40),
    ];
    expect(avgCyrillicRatio(samples)).toBeGreaterThan(0.35);
    const englishHeavy = samples.filter(
      (l) => cyrillicRatio(l) < 0.15 && /\b[a-zA-Z]{5,}\b/.test(l),
    );
    expect(englishHeavy.length).toBeLessThan(samples.length * 0.15);
  });

  it("includes owl meme reference", () => {
    const all = [
      ...banterPools.ru.safe.player,
      ...banterPools.en.safe.player,
    ].join("\n");
    expect(all.toLowerCase()).toMatch(/owl|сова/);
  });
});

describe("shouldSpawnBanter", () => {
  it("respects damage threshold", () => {
    expect(shouldSpawnBanter(3, 1000, 0, 0)).toBe(false);
    expect(shouldSpawnBanter(10, 1000, 0, 0)).toBe(true);
  });

  it("respects cooldown", () => {
    expect(shouldSpawnBanter(10, 1000, 500, 0)).toBe(false);
    expect(shouldSpawnBanter(10, 2000, 500, 0)).toBe(true);
  });

  it("uses spawn chance", () => {
    expect(shouldSpawnBanter(10, 5000, 0, BANTER_SPAWN_CHANCE - 0.01)).toBe(
      true,
    );
    expect(shouldSpawnBanter(10, 5000, 0, BANTER_SPAWN_CHANCE + 0.01)).toBe(
      false,
    );
  });
});

describe("pickBanterLine", () => {
  it("returns non-empty lines", () => {
    const line = pickBanterLine("ru", false, "player");
    expect(line.length).toBeGreaterThan(0);
  });
});
