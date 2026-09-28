import type { AbilityId, FighterLoadout } from "./types";

/** Способности, которые сейчас читаются из input-флагов в abilityTick. */
export type GatedAbilityFlag = "dash" | "flip" | "brace";

/**
 * Если лодаута нет — полный классический набор (обратная совместимость).
 * Иначе способность должна быть в base или в слотах abilities.
 */
export function loadoutAllowsAbility(
  loadout: FighterLoadout | undefined | null,
  ability: GatedAbilityFlag,
): boolean {
  if (!loadout) return true;
  if (loadout.base === ability) return true;
  return loadout.abilities.some((slot) => slot === (ability as AbilityId));
}
