import {
  isBaseAbilityId,
  type AbilityId,
  type FighterLoadout,
  type PassiveItemId,
} from "./types";

/** Собирает классический 2+2 лодаут + хвосты для тест-арены. */
export function buildTestArenaLoadout(
  abilities: readonly AbilityId[],
  items: readonly PassiveItemId[],
): {
  loadout: FighterLoadout;
  extraItems: PassiveItemId[];
  castAbilities: AbilityId[];
} {
  const base =
    abilities.find(isBaseAbilityId) ??
    ("dash" as const);
  const nonBase = abilities.filter((id) => !isBaseAbilityId(id));
  const slot0 = nonBase[0] ?? abilities.find((id) => id !== base) ?? null;
  const slot1 = nonBase[1] ?? null;

  return {
    loadout: {
      base,
      abilities: [slot0, slot1],
      items: [items[0] ?? null, items[1] ?? null],
    },
    extraItems: items.slice(2),
    castAbilities: nonBase.length > 0 ? [...nonBase] : abilities.filter((id) => id !== base),
  };
}
