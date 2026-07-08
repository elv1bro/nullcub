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

export function isFriendlyWeaponHit(
  weapon: WeaponHitInfo,
  victimCompositeId: number,
  _aggressorCompositeId: number,
  bodyA: Body,
  bodyB: Body,
  compositeAId: number,
): boolean {
  if (!weapon.ownerFighterId) return false;
  const victimIsA = compositeAId === victimCompositeId;
  const aggressorBody = victimIsA ? bodyB : bodyA;
  const ownerOnAggressor = bodyBelongsToFighter(
    aggressorBody,
    weapon.ownerFighterId,
  );
  return ownerOnAggressor;
}
