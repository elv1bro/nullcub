/**
 * Урон только от «влетания» в соперника вдоль нормали удара.
 * Скольжение/объятия без подхода — без урона. Один залп на пару бойцов ~200 ms.
 */
import Matter from "matter-js";
import { isSaveBody } from "./isSaveBody";
import { resolveWeaponFromBody } from "@/items/resolveWeaponHit";

export const MAX_HP = 1000;
export const OPPONENT_MAX_HP = 1000;
/** Кулдаун на пару бойцов (не на каждый сегмент тела). */
export const FIGHTER_HIT_COOLDOWN_MS = 200;
/** Минимальная скорость сближения вдоль удара */
export const MIN_IMPACT_SPEED = 1.2;

/** Лёгкий recoil атакующему (~5%). */
export const ATTACKER_RECOIL = 0.05;

/** closing speed (≈1–10) → hearts */
export const DAMAGE_PER_SPEED = 11;

/** Бот бьёт сильнее по игроку. */
export const BOT_DAMAGE_MULTIPLIER = 1.4;

const ZONE_MULTIPLIER: Record<string, number> = {
  Head: 1.6,
  Chest: 1.0,
};

function zoneMultiplier(body: Matter.Body): number {
  if (isSaveBody(body)) return 0;
  if (body.label === "Armor") return 0;
  return ZONE_MULTIPLIER[body.label] ?? 0.85;
}

export interface DamageResult {
  damageA: number;
  damageB: number;
  victim: "a" | "b" | "both" | "none";
  impactSpeed: number;
  closing: number;
  damageTypeId?: string;
  damageColor?: string;
  weaponItemId?: string | null;
}

export function computeDamage(
  bodyA: Matter.Body,
  bodyB: Matter.Body,
): DamageResult {
  const delta = Matter.Vector.sub(bodyB.position, bodyA.position);
  const dist = Matter.Vector.magnitude(delta);
  if (dist < 1e-4) {
    return { damageA: 0, damageB: 0, victim: "none", impactSpeed: 0, closing: 0 };
  }

  const normal = Matter.Vector.div(delta, dist);

  // >0 — тела сближаются вдоль A→B
  const closing =
    Matter.Vector.dot(bodyA.velocity, normal) -
    Matter.Vector.dot(bodyB.velocity, normal);

  const impactSpeed = Math.max(0, closing);

  if (impactSpeed < MIN_IMPACT_SPEED) {
    return {
      damageA: 0,
      damageB: 0,
      victim: "none",
      impactSpeed,
      closing,
    };
  }

  const base = impactSpeed * DAMAGE_PER_SPEED;

  const weaponA = resolveWeaponFromBody(bodyA);
  const weaponB = resolveWeaponFromBody(bodyB);

  function scaleDamage(raw: number, weapon: ReturnType<typeof resolveWeaponFromBody>): number {
    if (!weapon) return raw;
    return raw * weapon.atkMult;
  }

  function metaFromWeapon(weapon: ReturnType<typeof resolveWeaponFromBody>) {
    if (!weapon) return {};
    return {
      damageTypeId: weapon.damageTypeId,
      damageColor: weapon.damageColor,
      weaponItemId: weapon.itemId,
    };
  }

  const approachA = Matter.Vector.dot(bodyA.velocity, normal);
  const approachB = -Matter.Vector.dot(bodyB.velocity, normal);

  // Оба влетели друг в друга: урон каждому масштабирует оружие АТАКУЮЩЕГО
  // (то есть чужое), не собственное.
  if (approachA > 0.4 && approachB > 0.4) {
    const half = 0.55;
    const weapon = weaponA ?? weaponB;
    return {
      damageA: scaleDamage(base * zoneMultiplier(bodyA) * half, weaponB),
      damageB: scaleDamage(base * zoneMultiplier(bodyB) * half, weaponA),
      victim: "both",
      impactSpeed,
      closing,
      ...metaFromWeapon(weapon),
    };
  }

  if (approachA >= approachB) {
    const victimDamage = scaleDamage(base * zoneMultiplier(bodyB), weaponA);
    if (victimDamage <= 0) {
      return { damageA: 0, damageB: 0, victim: "none", impactSpeed, closing };
    }
    return {
      damageA: victimDamage * ATTACKER_RECOIL,
      damageB: victimDamage,
      victim: "b",
      impactSpeed,
      closing,
      ...metaFromWeapon(weaponA),
    };
  }

  const victimDamage = scaleDamage(base * zoneMultiplier(bodyA), weaponB);
  if (victimDamage <= 0) {
    return { damageA: 0, damageB: 0, victim: "none", impactSpeed, closing };
  }
  return {
    damageA: victimDamage,
    damageB: victimDamage * ATTACKER_RECOIL,
    victim: "a",
    impactSpeed,
    closing,
    ...metaFromWeapon(weaponB),
  };
}
