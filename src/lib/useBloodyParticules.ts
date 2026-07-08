import { Particle } from "@/lib/Particle";
import {
  useEngineEvent,
  useEventBeforeUpdate,
} from "@1.framework/matter4react";
import debug from "debug";
import {
  Body,
  Common,
  Composite,
  Vector,
  type Engine,
  type IEventTimestamped,
} from "matter-js";
import { useRef, type DependencyList } from "react";
import { computeDamage } from "./combat";
import {
  type CombatFxConfig,
  resolveHitParties,
} from "./combatFx";
import { isSaveBody } from "./isSaveBody";
import { isKoScatteredId } from "./victoryKoScatter";
import { useStickmanCollision } from "./useStickmanCollision";

export const log = debug("@:lib:useBloodyParticules");

export function useBloodyParticules(
  composites: Composite[],
  config: CombatFxConfig,
  deps: DependencyList,
  battleOverRef?: { current: boolean },
) {
  log("!");
  const particules = useRef<Particle[]>([]);
  const dead_particules = useRef<Particle[]>([]);

  useStickmanCollision(
    composites,
    {
      onCollisionStart: (event, { pair, compositeA, compositeB }) => {
        if (battleOverRef?.current) return;
        if (
          isKoScatteredId(compositeA, composites) ||
          isKoScatteredId(compositeB, composites)
        ) {
          return;
        }

        const contact = pair.collision.supports.at(0);
        if (!contact) return;
        if ([pair.bodyA, pair.bodyB].every(isSaveBody)) return;

        const result = computeDamage(pair.bodyA, pair.bodyB);
        if (result.damageA <= 0 && result.damageB <= 0) return;

        const parties = resolveHitParties(result, compositeA, compositeB, config);
        if (!parties.length) return;

        const main = parties.reduce((a, b) =>
          b.victimDamage > a.victimDamage ? b : a,
        );

        const imp = 1 / 10000;
        const impactVelocity = Vector.magnitude(pair.collision.penetration) * 2;
        const particleCount = Math.min(
          80,
          Math.max(12, Math.floor(impactVelocity * main.victimDamage * 0.08)),
        );

        particules.current = Array.from({ length: particleCount })
          .map(
            () =>
              new Particle(
                contact.x,
                contact.y,
                1.5 + Common.random(0, 2),
                main.victimColors.main,
              ),
          )
          .map((p) => {
            Composite.add(event.source.world, p.body);
            Body.applyForce(p.body, p.body.position, {
              x: Common.random(-imp, imp),
              y: Common.random(-imp, imp),
            });
            return p;
          })
          .concat(particules.current);
      },
    },
    deps,
  );

  useEventBeforeUpdate((event) => {
    dead_particules.current = [];
    const active_particules = particules.current;
    particules.current = [];
    for (const p of active_particules) {
      p.update(event);
      if (p.life <= 0) {
        dead_particules.current.push(p);
        continue;
      }
      particules.current.push(p);
    }
  }, deps);

  useEngineEvent(
    "afterUpdate",
    (event: IEventTimestamped<Engine>) => {
      for (const p of dead_particules.current) {
        Composite.remove(event.source.world, p.body);
      }
    },
    deps,
  );
}
