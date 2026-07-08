import { useEventBeforeUpdate } from "@1.framework/matter4react";
import * as colorString from "color-string";
import debug from "debug";
import { Body, Vector, type Composite } from "matter-js";
import { useRef, type DependencyList } from "react";
import { computeDamage, FIGHTER_HIT_COOLDOWN_MS } from "./combat";
import { computeKnockback } from "./knockback";
import {
  type CombatFxConfig,
  resolveHitParties,
} from "./combatFx";
import { isSaveBody } from "./isSaveBody";
import { moveBody } from "./moveBody";
import { useStickmanCollision } from "./useStickmanCollision";

export const log = debug("@:lib:useImpactHandler");

type ImpactEntry = {
  body: Body;
  strength: number;
  vec: Vector;
  tintColor: string | null;
};

import {
  KNOCKBACK_SPEED,
  BRACE_KNOCKBACK_MULT,
} from "./battleTuning";
import { clampBodySpeed } from "./bodySpeed";
import { isBattleSpawnGrace } from "./combatGrace";
import { isKoScatteredId } from "./victoryKoScatter";

function lerpColor(
  from: string,
  toward: string,
  t: number,
): string {
  const a = colorString.get.rgb(from);
  const b = colorString.get.rgb(toward);
  if (!a || !b) return toward;
  const mix = (x: number, y: number) => Math.round(x + (y - x) * t);
  return colorString.to.hex([
    mix(a[0], b[0]),
    mix(a[1], b[1]),
    mix(a[2], b[2]),
  ]);
}

function clampBodySpeedLocal(body: Body): void {
  clampBodySpeed(body);
}

export function useImpactHandler(
  composites: Composite[],
  config: CombatFxConfig,
  deps: DependencyList,
  battleStartRef?: { current: number },
  battleOverRef?: { current: boolean },
  braceActiveRef?: { current: boolean },
  enabled = true,
) {
  log("!");
  const body_colors_ref = useRef(new Map<number, string>());
  const impactedBody = useRef<ImpactEntry[]>([]);
  const knockbackCooldown = useRef(new Map<string, number>());

  useStickmanCollision(
    composites,
    {
      onCollisionStart: (_event, { pair: { bodyA, bodyB, collision }, compositeA, compositeB }) => {
        if (!enabled) return;
        if (battleOverRef?.current) return;
        if (
          isKoScatteredId(compositeA, composites) ||
          isKoScatteredId(compositeB, composites)
        ) {
          return;
        }

        const contact = collision.supports.at(0);
        if (!contact) return;

        if (isBattleSpawnGrace(battleStartRef?.current ?? 0)) return;

        if ([bodyA, bodyB].every(isSaveBody)) return;

        const result = computeDamage(bodyA, bodyB);
        if (result.damageA <= 0 && result.damageB <= 0) return;

        const fighterKey = `${Math.min(compositeA, compositeB)}-${Math.max(compositeA, compositeB)}`;
        const now = performance.now();
        if ((knockbackCooldown.current.get(fighterKey) ?? 0) > now) return;
        knockbackCooldown.current.set(fighterKey, now + FIGHTER_HIT_COOLDOWN_MS);

        const parties = resolveHitParties(result, compositeA, compositeB, config);
        if (!parties.length) return;

        const bodyId_to_color = body_colors_ref.current;
        const knockback = computeKnockback(result, bodyA, bodyB);
        const pushScale = Math.min(1.35, 0.55 + result.impactSpeed / 10);

        bodyId_to_color.has(bodyA.id) ||
          bodyId_to_color.set(bodyA.id, bodyA.render.fillStyle!);
        bodyId_to_color.has(bodyB.id) ||
          bodyId_to_color.set(bodyB.id, bodyB.render.fillStyle!);

        const victimIds = new Set(parties.map((p) => p.victimCompositeId));
        const playerBraced =
          !!braceActiveRef?.current &&
          config.playerCompositeId !== undefined &&
          victimIds.has(config.playerCompositeId);

        const pushImpact = (
          body: Body,
          compositeId: number,
          impulse: Vector,
        ) => {
          const mag = Vector.magnitude(impulse);
          if (mag < 1e-6) return;

          const party = parties.find((p) => p.victimCompositeId === compositeId);
          let strength = pushScale;
          if (
            playerBraced &&
            config.playerCompositeId !== undefined &&
            compositeId === config.playerCompositeId
          ) {
            strength *= BRACE_KNOCKBACK_MULT;
          }

          impactedBody.current.push({
            body,
            strength,
            vec: Vector.div(impulse, mag),
            tintColor:
              victimIds.has(compositeId) && party && !isSaveBody(body)
                ? party.aggressorColors.main
                : null,
          });
        };

        pushImpact(bodyA, compositeA, knockback.impulseA);
        pushImpact(bodyB, compositeB, knockback.impulseB);
      },
    },
    deps,
  );

  useEventBeforeUpdate((event) => {
    if (battleOverRef?.current) {
      impactedBody.current = [];
      return;
    }

    const timeScale = (event as { delta?: number }).delta ?? 16.667;
    const timeStep = timeScale / 1_000;
    const bodyId_to_color = body_colors_ref.current;
    const { current: impacts } = impactedBody;
    const nextImpactedBody: ImpactEntry[] = [];

    while (impacts.length > 0) {
      const impact = impacts.pop();
      if (!impact) break;

      const { body, strength, vec, tintColor } = impact;
      const color = bodyId_to_color.get(body.id);
      if (!color || isSaveBody(body)) continue;

      if (tintColor) {
        body.render.fillStyle = lerpColor(color, tintColor, strength * 0.92);
      }

      moveBody(body)(event, vec, KNOCKBACK_SPEED * strength);
      clampBodySpeedLocal(body);

      if (strength > timeStep) {
        nextImpactedBody.push({
          body,
          strength: strength - timeStep,
          vec,
          tintColor,
        });
      } else if (color) {
        body.render.fillStyle = color;
      }
    }

    impactedBody.current = nextImpactedBody;
  }, deps);
}
