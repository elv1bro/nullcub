import { Body, Vector } from "matter-js";
import type { AbilityId } from "./types";
import { getAbilityDef, isWiredBaseAbility } from "./abilities";
import { ABILITY_META } from "./catalogMeta";

export type CastAbilityResult =
  | { ok: true; kind: "base"; base: "dash" | "flip" | "brace" }
  | { ok: true; kind: "effect"; durationMs: number }
  | { ok: false; reason: "unknown" | "passive" };

/**
 * Активация способности из слота лодаута.
 * dash/flip/brace — делегируем в abilityTick; остальное — видимый «lab cast».
 */
export function resolveLoadoutCast(abilityId: AbilityId): CastAbilityResult {
  if (isWiredBaseAbility(abilityId)) {
    return { ok: true, kind: "base", base: abilityId };
  }
  const def = getAbilityDef(abilityId);
  if (def.kind === "passive") {
    return { ok: false, reason: "passive" };
  }
  return {
    ok: true,
    kind: "effect",
    durationMs: def.durationMs ?? 900,
  };
}

/** Импульс / краткий баф по категории (для stub-активок в лабе и рогалике). */
export function applyLoadoutCastEffect(
  head: Body,
  abilityId: AbilityId,
  move: Vector,
): void {
  const cat = ABILITY_META[abilityId]?.cat ?? "utility";
  const dir =
    Math.hypot(move.x, move.y) > 0.15
      ? Vector.normalise(move)
      : Vector.create(head.velocity.x >= 0 ? 1 : -1, 0);

  const impulseFor = (scale: number) =>
    Vector.create(dir.x * scale, dir.y * scale);

  switch (cat) {
    case "mobility":
      Body.setVelocity(head, {
        x: head.velocity.x + dir.x * 14,
        y: head.velocity.y + dir.y * 14,
      });
      break;
    case "offense":
      Body.applyForce(head, head.position, impulseFor(0.045));
      break;
    case "defense":
      Body.setVelocity(head, {
        x: head.velocity.x * 0.35,
        y: head.velocity.y * 0.35,
      });
      break;
    case "control":
      Body.applyForce(head, head.position, impulseFor(0.028));
      break;
    case "support":
      Body.setVelocity(head, {
        x: head.velocity.x + dir.x * 6,
        y: head.velocity.y - 8,
      });
      break;
    case "chaos":
      Body.setAngularVelocity(head, (Math.random() > 0.5 ? 1 : -1) * 0.55);
      Body.applyForce(head, head.position, impulseFor(0.032));
      break;
    default:
      Body.applyForce(head, head.position, impulseFor(0.03));
      break;
  }
}

export function loadoutSlotAbilityCooldownMs(abilityId: AbilityId): number {
  return getAbilityDef(abilityId).cooldownMs ?? 6000;
}
