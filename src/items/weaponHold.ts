import Matter, { Body, type Body as MatterBody, type Composite } from "matter-js";
import type { FighterGrabState, HandSide } from "@/lib/grab/types";
import { grabPlugin } from "@/lib/grab/types";
import {
  itemLeafBodies,
  resolveConstraintBody,
  weaponHoldMoveMult,
  weaponMassOf,
} from "./buildItem";

export function itemOwnerId(composite: Composite): string | null {
  for (const body of composite.bodies) {
    const owner = grabPlugin(body).ownerFighterId;
    if (owner) return owner;
  }
  for (const body of itemLeafBodies(composite)) {
    const owner = grabPlugin(body).ownerFighterId;
    if (owner) return owner;
  }
  return null;
}

/** Тело для pin (цельное оружие или grip-бусина). */
export function findGripBody(composite: Composite): Body | undefined {
  const solid = composite.bodies.find(
    (b) =>
      Boolean((b.plugin as { itemSolid?: boolean })?.itemSolid) ||
      Boolean(grabPlugin(b).gripOf),
  );
  if (solid) return solid;

  for (const b of itemLeafBodies(composite)) {
    if (b.label === "Grip" || Boolean(grabPlugin(b).gripOf)) return b;
  }
  return composite.bodies[0];
}

/** Смещение направляющей от grip вдоль локальной оси X оружия. */
export const WEAPON_GUIDE_ALONG = 14;

/** Мировая точка рукояти (gripLocal или COM тела). */
export function gripWorldPoint(composite: Composite): { x: number; y: number } {
  const grip = findGripBody(composite);
  if (!grip) return compositeCom(composite);
  const local = (grip.plugin as { gripLocal?: { x: number; y: number } })
    ?.gripLocal;
  if (!local) return { x: grip.position.x, y: grip.position.y };
  const rotated = Matter.Vector.rotate(local, grip.angle);
  return {
    x: grip.position.x + rotated.x,
    y: grip.position.y + rotated.y,
  };
}

/**
 * Точка на рукояти чуть дальше grip — для мягкой направляющей вдоль руки.
 */
export function guideWorldPoint(composite: Composite): { x: number; y: number } {
  const grip = findGripBody(composite);
  if (!grip) return compositeCom(composite);
  const local = (grip.plugin as { gripLocal?: { x: number; y: number } })
    ?.gripLocal ?? { x: 0, y: 0 };
  const guideLocal = { x: local.x + WEAPON_GUIDE_ALONG, y: local.y };
  const rotated = Matter.Vector.rotate(guideLocal, grip.angle);
  return {
    x: grip.position.x + rotated.x,
    y: grip.position.y + rotated.y,
  };
}

/** Перед pin: рукоять в кисть, без растянутого constraint. */
export function snapWeaponGripToHand(
  composite: Composite,
  hand: MatterBody,
): void {
  const grip = findGripBody(composite);
  if (!grip) return;
  const pinBody = resolveConstraintBody(grip);
  const gripWorld = gripWorldPoint(composite);
  Body.translate(pinBody, {
    x: hand.position.x - gripWorld.x,
    y: hand.position.y - gripWorld.y,
  });
  Body.setVelocity(pinBody, { ...hand.velocity });
  Body.setAngularVelocity(pinBody, hand.angularVelocity * 0.25);
}

/** Held weapon vs own ragdoll — не резолвить (иначе pin борется с коллизией). */
export function isHeldWeaponVsOwner(
  a: MatterBody,
  b: MatterBody,
): boolean {
  const aOwner = grabPlugin(a).ownerFighterId;
  const bOwner = grabPlugin(b).ownerFighterId;
  const aFighter = grabPlugin(a).fighterId;
  const bFighter = grabPlugin(b).fighterId;
  if (aOwner && bFighter && aOwner === bFighter) return true;
  if (bOwner && aFighter && bOwner === aFighter) return true;
  return false;
}

export function compositeCom(composite: Composite): { x: number; y: number } {
  const list =
    composite.bodies.length === 1
      ? composite.bodies
      : itemLeafBodies(composite);
  let x = 0;
  let y = 0;
  const n = list.length || 1;
  for (const b of list) {
    x += b.position.x;
    y += b.position.y;
  }
  return { x: x / n, y: y / n };
}

export function dist2(
  a: { x: number; y: number },
  b: { x: number; y: number },
): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return dx * dx + dy * dy;
}

export function pickFreeHand(grab: FighterGrabState): HandSide | null {
  if (grab.left.phase !== "attached") return "left";
  if (grab.right.phase !== "attached") return "right";
  return null;
}

export function handHoldsWeapon(
  grab: FighterGrabState,
  side: HandSide,
): boolean {
  const hand = side === "left" ? grab.left : grab.right;
  if (hand.phase !== "attached" || !hand.target) return false;
  return hand.target.kind === "grip" || hand.target.kind === "item";
}

export function isHoldingAnyWeapon(grab: FighterGrabState): boolean {
  return handHoldsWeapon(grab, "left") || handHoldsWeapon(grab, "right");
}

export interface NearestWeaponResult {
  composite: Composite;
  /** Тело для Matter.Constraint (parent / solid). */
  pinBody: Body;
  gripWorld: { x: number; y: number };
  distSq: number;
}

/**
 * Ближайшее оружие без владельца в радиусе (по точке рукояти).
 */
export function findNearestUnownedWeapon(
  from: { x: number; y: number },
  itemComposites: Composite[],
  range: number,
): NearestWeaponResult | null {
  const rangeSq = range * range;
  let best: NearestWeaponResult | null = null;
  for (const composite of itemComposites) {
    if (itemOwnerId(composite)) continue;
    const grip = findGripBody(composite);
    if (!grip) continue;
    const pinBody = resolveConstraintBody(grip);
    const gripWorld = gripWorldPoint(composite);
    const d = dist2(from, gripWorld);
    if (d > rangeSq) continue;
    if (!best || d < best.distSq) {
      best = { composite, pinBody, gripWorld, distSq: d };
    }
  }
  return best;
}

/** Штраф к moveSpeedMult от оружия в руках бойца. */
export function heldWeaponMoveMult(
  grab: FighterGrabState,
  itemComposites: Composite[],
): number {
  let worst = 1;
  for (const side of ["left", "right"] as const) {
    if (!handHoldsWeapon(grab, side)) continue;
    const hand = side === "left" ? grab.left : grab.right;
    const target = hand.target;
    if (!target) continue;
    const item =
      (target.compositeId != null
        ? itemComposites.find((c) => c.id === target.compositeId)
        : undefined) ??
      itemComposites.find(
        (c) =>
          c.bodies.some((b) => b.id === target.bodyId) ||
          itemLeafBodies(c).some((b) => b.id === target.bodyId),
      );
    if (!item) continue;
    worst = Math.min(worst, weaponHoldMoveMult(weaponMassOf(item)));
  }
  return worst;
}

export {
  weaponHoldMoveMult,
  weaponMassOf,
  resolveConstraintBody,
} from "./buildItem";
