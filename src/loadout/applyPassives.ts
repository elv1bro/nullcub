import { getItemDef } from "./items";
import type { FighterLoadout, PassiveItemId } from "./types";

export interface LoadoutCombatMods {
  atkMult: number;
  /** Процент снижения урона (как CoreFighterSpec.defensePct). */
  defPct: number;
  moveMult: number;
  knockbackOutMult: number;
  critChance: number;
  headDefBonus: number;
}

const IDENTITY_MODS: LoadoutCombatMods = {
  atkMult: 1,
  defPct: 0,
  moveMult: 1,
  knockbackOutMult: 1,
  critChance: 0,
  headDefBonus: 0,
};

/** Сводит список предметов в боевые модификаторы (тест-арена: много слотов). */
export function computeItemCombatMods(
  itemIds: readonly (PassiveItemId | null | undefined)[],
): LoadoutCombatMods {
  let atkMult = 1;
  let defMultProduct = 1;
  let moveMult = 1;
  let knockbackOutMult = 1;
  let critChance = 0;
  let headDefBonus = 0;
  let hasDef = false;

  for (const itemId of itemIds) {
    if (!itemId) continue;
    const def = getItemDef(itemId);
    if (def.atkMult != null) atkMult *= def.atkMult;
    if (def.defMult != null) {
      defMultProduct *= def.defMult;
      hasDef = true;
    }
    if (def.moveMult != null) moveMult *= def.moveMult;
    if (def.knockbackOutMult != null) {
      knockbackOutMult *= def.knockbackOutMult;
    }
    if (def.critChance != null) critChance += def.critChance;
    if (def.headDefBonus != null) headDefBonus += def.headDefBonus;
  }

  if (
    atkMult === 1 &&
    !hasDef &&
    moveMult === 1 &&
    knockbackOutMult === 1 &&
    critChance === 0 &&
    headDefBonus === 0
  ) {
    return IDENTITY_MODS;
  }

  return {
    atkMult,
    defPct: hasDef ? (defMultProduct - 1) * 100 : 0,
    moveMult,
    knockbackOutMult,
    critChance,
    headDefBonus,
  };
}

/** Сводит пассивные предметы лодаута (+ опциональный хвост) в боевые модификаторы. */
export function computeLoadoutCombatMods(
  loadout: FighterLoadout,
  extraItems?: readonly (PassiveItemId | null | undefined)[],
): LoadoutCombatMods {
  return computeItemCombatMods([
    ...loadout.items,
    ...(extraItems ?? []),
  ]);
}
