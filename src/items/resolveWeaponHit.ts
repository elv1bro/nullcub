import { type Body } from "matter-js";
import { items } from "./registry";
import { getDamageType } from "./damageTypes";

/** Шип из мастерской — «природное оружие», колющий урон. */
export const SPIKE_ATK_MULT = 1.7;

export interface WeaponHitInfo {
  atkMult: number;
  damageTypeId: string;
  damageColor: string;
  itemId: string | null;
  ownerFighterId: string | null;
}

export function resolveWeaponFromBody(body: Body): WeaponHitInfo | null {
  const plugin = (body.plugin ?? {}) as {
    itemId?: string;
    ownerFighterId?: string;
    spikeWeapon?: boolean;
  };
  if (plugin.itemId) {
    const def = items.get(plugin.itemId);
    const dtype = getDamageType(def.damageType);
    return {
      atkMult: def.atkMult,
      damageTypeId: def.damageType,
      damageColor: dtype.color,
      itemId: def.id,
      ownerFighterId: plugin.ownerFighterId ?? null,
    };
  }
  if (plugin.spikeWeapon || body.label === "Spike") {
    const dtype = getDamageType("pierce");
    return {
      atkMult: SPIKE_ATK_MULT,
      damageTypeId: "pierce",
      damageColor: dtype.color,
      itemId: null,
      ownerFighterId: null,
    };
  }
  return null;
}

export function bodyBelongsToFighter(body: Body, fighterId: string): boolean {
  return (body.plugin as { fighterId?: string })?.fighterId === fighterId;
}

/**
 * Оружие в руках не должно бить владельца.
 * ownerFighterId на теле оружия → id бойца-жертвы.
 */
export function isFriendlyWeaponHit(
  weapon: WeaponHitInfo | null | undefined,
  victimFighterId: string | undefined | null,
): boolean {
  if (!weapon?.ownerFighterId || !victimFighterId) return false;
  return weapon.ownerFighterId === victimFighterId;
}

/** Обнуляет урон владельцу от его же оружия (и recoil в оружие). */
export function filterFriendlyWeaponDamage(
  bodyA: Body,
  bodyB: Body,
  fighterAId: string | undefined,
  fighterBId: string | undefined,
  damageA: number,
  damageB: number,
): { damageA: number; damageB: number } {
  const weaponA = resolveWeaponFromBody(bodyA);
  const weaponB = resolveWeaponFromBody(bodyB);
  let nextA = damageA;
  let nextB = damageB;

  // A — оружие, бьёт владельца B
  if (isFriendlyWeaponHit(weaponA, fighterBId)) {
    nextB = 0;
    nextA = 0;
  }
  // B — оружие, бьёт владельца A
  if (isFriendlyWeaponHit(weaponB, fighterAId)) {
    nextA = 0;
    nextB = 0;
  }
  return { damageA: nextA, damageB: nextB };
}
