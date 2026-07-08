import Matter from "matter-js";
import { computeDamage, type DamageResult } from "./combat";

/** Сила отталкивания от скорости удара. */
export const KNOCKBACK_PER_IMPACT_SPEED = 1.5;

/** Доп. отталкивание от урона. */
export const KNOCKBACK_PER_DAMAGE = 0.06;

/** Доля импульса на атакующего (отдача). */
export const KNOCKBACK_ATTACKER_SCALE = 0.38;

export interface KnockbackResult {
  impulseA: Matter.Vector;
  impulseB: Matter.Vector;
  victimMagnitude: number;
}

function scaleImpulse(vec: Matter.Vector, mass: number, mag: number): Matter.Vector {
  const len = Matter.Vector.magnitude(vec);
  if (len < 1e-6) return { x: 0, y: 0 };
  return Matter.Vector.mult(Matter.Vector.div(vec, len), mag * Math.sqrt(mass));
}

/** Импульс разлёта по результату урона. */
export function computeKnockback(
  result: DamageResult,
  bodyA: Matter.Body,
  bodyB: Matter.Body,
): KnockbackResult {
  const delta = Matter.Vector.sub(bodyB.position, bodyA.position);
  const dist = Matter.Vector.magnitude(delta);
  if (dist < 1e-4 || result.victim === "none") {
    return {
      impulseA: { x: 0, y: 0 },
      impulseB: { x: 0, y: 0 },
      victimMagnitude: 0,
    };
  }

  const awayFromB = Matter.Vector.normalise(Matter.Vector.sub(bodyA.position, bodyB.position));
  const awayFromA = Matter.Vector.neg(awayFromB);

  const peakDamage = Math.max(result.damageA, result.damageB);
  const mag =
    result.impactSpeed * KNOCKBACK_PER_IMPACT_SPEED +
    peakDamage * KNOCKBACK_PER_DAMAGE;

  if (result.victim === "both") {
    const half = mag * 0.72;
    return {
      impulseA: scaleImpulse(awayFromB, bodyA.mass, half),
      impulseB: scaleImpulse(awayFromA, bodyB.mass, half),
      victimMagnitude: half,
    };
  }

  if (result.victim === "b") {
    return {
      impulseA: scaleImpulse(awayFromB, bodyA.mass, mag * KNOCKBACK_ATTACKER_SCALE),
      impulseB: scaleImpulse(awayFromA, bodyB.mass, mag),
      victimMagnitude: mag,
    };
  }

  return {
    impulseA: scaleImpulse(awayFromB, bodyA.mass, mag),
    impulseB: scaleImpulse(awayFromA, bodyB.mass, mag * KNOCKBACK_ATTACKER_SCALE),
    victimMagnitude: mag,
  };
}

export interface StrikePreview {
  damage: DamageResult;
  knockback: KnockbackResult;
  closingSpeed: number;
}

/** Превью удара для лаборатории (без физики). */
export function previewStrike(
  attacker: Matter.Body,
  target: Matter.Body,
  closingSpeed: number,
): StrikePreview {
  const delta = Matter.Vector.sub(target.position, attacker.position);
  const dist = Matter.Vector.magnitude(delta);
  if (dist < 1e-4) {
    const empty = {
      damageA: 0,
      damageB: 0,
      victim: "none" as const,
      impactSpeed: 0,
      closing: 0,
    };
    return {
      damage: empty,
      knockback: computeKnockback(empty, attacker, target),
      closingSpeed,
    };
  }

  const dir = Matter.Vector.div(delta, dist);
  const a = Matter.Bodies.circle(attacker.position.x, attacker.position.y, 10, {
    label: attacker.label,
  });
  const b = Matter.Bodies.circle(target.position.x, target.position.y, 10, {
    label: target.label,
  });
  Matter.Body.setVelocity(a, Matter.Vector.mult(dir, closingSpeed));
  Matter.Body.setVelocity(b, { x: 0, y: 0 });

  const damage = computeDamage(a, b);
  return {
    damage,
    knockback: computeKnockback(damage, a, b),
    closingSpeed,
  };
}

/** Применить импульс как в бою (moveBody, SPEED = -42). */
function applyCombatImpulse(body: Matter.Body, impulse: Matter.Vector) {
  const dt = 1000 / 60;
  Matter.Body.applyForce(
    body,
    body.position,
    Matter.Vector.mult(impulse, (-42 * body.mass) / dt),
  );
}

/** Применить удар в лаборатории. */
export function applyLabStrike(
  attacker: Matter.Body,
  target: Matter.Body,
  closingSpeed: number,
): StrikePreview {
  const delta = Matter.Vector.sub(target.position, attacker.position);
  const dist = Matter.Vector.magnitude(delta);
  if (dist < 1e-4) {
    return previewStrike(attacker, target, closingSpeed);
  }

  const dir = Matter.Vector.div(delta, dist);
  Matter.Body.setVelocity(attacker, Matter.Vector.mult(dir, closingSpeed));
  Matter.Body.setVelocity(target, { x: 0, y: 0 });
  Matter.Body.setAngularVelocity(target, 0);

  const damage = computeDamage(attacker, target);
  const knockback = computeKnockback(damage, attacker, target);
  applyCombatImpulse(attacker, knockback.impulseA);
  applyCombatImpulse(target, knockback.impulseB);

  return { damage, knockback, closingSpeed };
}

export const STRIKE_LIMB_LABELS = [
  "Head",
  "Chest",
  "Upper Left Arm",
  "Upper Right Arm",
  "Lower Left Arm",
  "Lower Right Arm",
  "Upper Left Leg",
  "Upper Right Leg",
] as const;

export type StrikeLimbLabel = (typeof STRIKE_LIMB_LABELS)[number];
