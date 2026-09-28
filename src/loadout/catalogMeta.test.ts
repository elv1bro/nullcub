import { describe, expect, it } from "vitest";
import { ABILITY_DEFS, draftableAbilityIds } from "./abilities";
import { ABILITY_META, ITEM_META } from "./catalogMeta";
import { ITEM_DEFS, allItemIds } from "./items";
import { ALL_ABILITY_IDS, PASSIVE_ITEM_IDS } from "./types";
import { rarityForCard } from "@/roguelike/lootRarity";

describe("roguelike catalog", () => {
  it("has 100 abilities and 100 items", () => {
    expect(ALL_ABILITY_IDS).toHaveLength(100);
    expect(PASSIVE_ITEM_IDS).toHaveLength(100);
    expect(Object.keys(ABILITY_DEFS)).toHaveLength(100);
    expect(Object.keys(ITEM_DEFS)).toHaveLength(100);
    expect(Object.keys(ABILITY_META)).toHaveLength(100);
    expect(Object.keys(ITEM_META)).toHaveLength(100);
  });

  it("draft pool excludes base trio", () => {
    const draft = draftableAbilityIds();
    expect(draft).toHaveLength(97);
    expect(draft).not.toContain("dash");
    expect(draft).not.toContain("flip");
    expect(draft).not.toContain("brace");
    expect(allItemIds()).toHaveLength(100);
  });

  it("every card has a rarity", () => {
    for (const id of ALL_ABILITY_IDS) {
      expect(rarityForCard(id)).toBeTruthy();
    }
    for (const id of PASSIVE_ITEM_IDS) {
      expect(rarityForCard(id)).toBeTruthy();
    }
  });
});
