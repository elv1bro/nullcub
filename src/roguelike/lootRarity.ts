import {
  isAbilityId,
  isBaseAbilityId,
  isPassiveItemId,
  type DraftCardId,
} from "@/loadout/types";
import {
  ABILITY_META,
  ITEM_META,
  type LootRarity,
} from "@/loadout/catalogMeta";

export type { LootRarity };

/** Редкость для визуала дропа (цвет рамки / бейдж). */
export function rarityForCard(card: DraftCardId): LootRarity {
  if (isBaseAbilityId(card)) return "common";
  if (isPassiveItemId(card)) return ITEM_META[card].rarity;
  if (isAbilityId(card)) return ABILITY_META[card].rarity;
  return "uncommon";
}
