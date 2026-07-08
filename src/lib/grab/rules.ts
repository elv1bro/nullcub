import type { DamageResult } from "@/lib/combat";
import {
  GRAB_ATTACH_DAMAGE_GRACE_MS,
  GRAB_FORCED_RELEASE_HITS,
  GRAB_FORCED_RELEASE_WINDOW_MS,
  type FighterGrabState,
  type HandSide,
} from "./types";

export interface GrabDamageContext {
  playerCompositeId?: number;
  opponentCompositeId?: number;
  playerGrab: FighterGrabState | null;
  opponentGrab: FighterGrabState | null;
}

/**
 * Жертва в захвате бьёт держателя со СНИЖЕННЫМ уроном: полный урон делал
 * захват самоубийственным (бенчмарк: грэбающие hard/boss проигрывали easy
 * всухую — жертва трепыхается через constraint и забивает держателя).
 * Не 0 — чтобы вырываться ударами (forced release) оставалось осмысленным.
 */
export const GRAB_HOLDER_INCOMING_DAMAGE_MULT = 0.3;

/** Урон держателя по захваченной жертве (не 0 — иначе грэб = проигрыш по DPS). */
export const GRAB_ATTACK_DAMAGE_MULT = 0.55;

/** Держатель бьёт захваченного ослабленно; сам получает от него меньше. */
export function filterGrabDamage(
  compositeAId: number,
  compositeBId: number,
  result: DamageResult,
  ctx: GrabDamageContext,
): DamageResult {
  let { damageA, damageB, victim } = result;
  if (victim === "none") return result;

  const aIsPlayer = compositeAId === ctx.playerCompositeId;
  const bIsPlayer = compositeBId === ctx.playerCompositeId;

  const aGrab = aIsPlayer ? ctx.playerGrab : ctx.opponentGrab;
  const bGrab = bIsPlayer ? ctx.playerGrab : ctx.opponentGrab;

  if (aGrab && holdsComposite(aGrab, compositeBId)) {
    if (victim === "b" || victim === "both") {
      damageB *= GRAB_ATTACK_DAMAGE_MULT;
      if (victim === "both") victim = damageA > 0 ? "both" : "a";
      else if (damageB <= 0 && damageA <= 0) victim = "none";
    }
    damageA *= GRAB_HOLDER_INCOMING_DAMAGE_MULT;
  }

  if (bGrab && holdsComposite(bGrab, compositeAId)) {
    if (victim === "a" || victim === "both") {
      damageA *= GRAB_ATTACK_DAMAGE_MULT;
      if (victim === "both") victim = damageB > 0 ? "both" : "b";
      else if (damageA <= 0 && damageB <= 0) victim = "none";
    }
    damageB *= GRAB_HOLDER_INCOMING_DAMAGE_MULT;
  }

  return { ...result, damageA, damageB, victim };
}

function holdsComposite(grab: FighterGrabState, compositeId: number): boolean {
  for (const hand of [grab.left, grab.right]) {
    if (hand.phase !== "attached") continue;
    if (hand.target?.compositeId === compositeId) return true;
    if (hand.target?.kind === "fighter" && hand.target.compositeId === compositeId) {
      return true;
    }
  }
  return false;
}

export interface GrabHitTracker {
  hits: number[];
}

export function createGrabHitTracker(): GrabHitTracker {
  return { hits: [] };
}

/** 2 удара по держателю за 1 с → forced release рук, держащих жертву. */
export function recordGrabVictimHit(
  tracker: GrabHitTracker,
  now: number,
): boolean {
  tracker.hits.push(now);
  tracker.hits = tracker.hits.filter(
    (t) => now - t <= GRAB_FORCED_RELEASE_WINDOW_MS,
  );
  return tracker.hits.length >= GRAB_FORCED_RELEASE_HITS;
}

export function shouldForceReleaseGrabber(
  grabberGrab: FighterGrabState,
  victimCompositeId: number,
): HandSide[] {
  const sides: HandSide[] = [];
  if (
    grabberGrab.left.phase === "attached" &&
    grabberGrab.left.target?.compositeId === victimCompositeId
  ) {
    sides.push("left");
  }
  if (
    grabberGrab.right.phase === "attached" &&
    grabberGrab.right.target?.compositeId === victimCompositeId
  ) {
    sides.push("right");
  }
  return sides;
}

export function isGrabbingFighter(
  grab: FighterGrabState | null,
  compositeId: number,
): boolean {
  if (!grab) return false;
  return holdsComposite(grab, compositeId);
}

/** Пропускаем урон сразу после прилипания — constraint даёт ложный «мега-удар». */
export function isGrabAttachDamageGrace(
  grab: FighterGrabState | null,
  now: number,
): boolean {
  if (!grab) return false;
  for (const hand of [grab.left, grab.right]) {
    if (hand.phase !== "attached" || !hand.attachedAt) continue;
    if (now - hand.attachedAt < GRAB_ATTACH_DAMAGE_GRACE_MS) return true;
  }
  return false;
}
