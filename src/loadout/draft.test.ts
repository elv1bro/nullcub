import { describe, expect, it } from "vitest";
import { draftableAbilityIds } from "./abilities";
import { allItemIds } from "./items";
import {
  allDraftableCards,
  buildDraftPool,
  claimCard,
  releaseCard,
} from "./draft";
import { BASE_ABILITY_IDS, isAbilityId, isPassiveItemId } from "./types";

/** Детерминированный rng: последовательность 0, 0.1, 0.2, … */
function seqRng(values: number[]): () => number {
  let i = 0;
  return () => {
    const v = values[i % values.length] ?? 0;
    i += 1;
    return v;
  };
}

describe("buildDraftPool", () => {
  it("returns playerCount + 1 unique cards", () => {
    const pool = buildDraftPool(3, () => 0.42);
    expect(pool).toHaveLength(4);
    expect(new Set(pool).size).toBe(pool.length);
  });

  it("never includes base abilities", () => {
    const pool = buildDraftPool(8, () => 0.3);
    for (const card of pool) {
      expect((BASE_ABILITY_IDS as readonly string[]).includes(card)).toBe(
        false,
      );
    }
  });

  it("mixes abilities and items from the draftable set", () => {
    const allowed = new Set(allDraftableCards());
    const pool = buildDraftPool(5, seqRng([0.9, 0.1, 0.5, 0.2, 0.7, 0.3]));
    expect(pool.length).toBe(6);
    for (const card of pool) {
      expect(allowed.has(card)).toBe(true);
      expect(isAbilityId(card) || isPassiveItemId(card)).toBe(true);
    }
  });

  it("caps at available unique cards", () => {
    const max = draftableAbilityIds().length + allItemIds().length;
    // playerCount+1 > max → пул обрезается по уникальным картам каталога
    const pool = buildDraftPool(max, () => 0.5);
    expect(pool.length).toBe(max);
    expect(new Set(pool).size).toBe(max);
  });
});

describe("claimCard / releaseCard", () => {
  it("claims a card from the pool into inventory", () => {
    const pool = ["shield", "gloves", "slam"] as const;
    const result = claimCard([...pool], {}, "p0", "gloves");
    expect(result.ok).toBe(true);
    expect(result.pool).toEqual(["shield", "slam"]);
    expect(result.inventoryByPlayer.p0).toEqual(["gloves"]);
  });

  it("fails claim when card is missing", () => {
    const pool = ["shield"] as const;
    const inv = { p0: ["gloves" as const] };
    const result = claimCard([...pool], inv, "p0", "slam");
    expect(result.ok).toBe(false);
    expect(result.pool).toEqual(["shield"]);
    expect(result.inventoryByPlayer).toEqual(inv);
  });

  it("releases a card back to the pool", () => {
    const claimed = claimCard(
      ["shield", "armor"],
      {},
      "p1",
      "armor",
    );
    const released = releaseCard(
      claimed.pool,
      claimed.inventoryByPlayer,
      "p1",
      "armor",
    );
    expect(released.ok).toBe(true);
    expect(released.pool).toContain("armor");
    expect(released.inventoryByPlayer.p1).toEqual([]);
  });

  it("fails release when player does not hold the card", () => {
    const result = releaseCard(["shield"], { p0: ["gloves"] }, "p0", "slam");
    expect(result.ok).toBe(false);
    expect(result.pool).toEqual(["shield"]);
  });
});
