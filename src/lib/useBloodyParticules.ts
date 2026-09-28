import {
  BLOODY_MAX_ALIVE,
  BLOODY_SPAWN_GAP_MS,
  particleCountForImpact,
  particleCountForReplayDamage,
  pruneBloodyParticles,
  spawnBloodyParticles,
} from "@/lib/bloodyParticles";
import { Particle } from "@/lib/Particle";
import {
  useEngine,
  useEngineEvent,
  useEventBeforeUpdate,
} from "@1.framework/matter4react";
import debug from "debug";
import {
  Composite,
  Vector,
  type Engine,
  type IEventTimestamped,
} from "matter-js";
import { useCallback, useRef, type DependencyList } from "react";
import { computeDamage } from "./combat";
import { type CombatFxConfig, resolveHitParties } from "./combatFx";
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
  const engine = useEngine();
  const particules = useRef<Particle[]>([]);
  const dead_particules = useRef<Particle[]>([]);
  const lastSpawnAt = useRef(0);

  const pushSpawned = useCallback(
    (spawned: Particle[]) => {
      if (!spawned.length) return;
      // Новые в начало — prune снимает хвост (самых старых).
      particules.current = spawned.concat(particules.current);
      pruneBloodyParticles(
        engine.world,
        particules.current,
        BLOODY_MAX_ALIVE,
      );
    },
    [engine],
  );

  const spawnAt = useCallback(
    (
      x: number,
      y: number,
      color: string,
      damageHint = 20,
      dir?: { x: number; y: number },
    ) => {
      const spawned = spawnBloodyParticles(engine.world, x, y, color, {
        count: particleCountForReplayDamage(damageHint),
        speed: 8 + Math.min(10, damageHint * 0.08),
        dirX: dir?.x,
        dirY: dir?.y,
        alive: particules.current.length,
      });
      pushSpawned(spawned);
    },
    [engine, pushSpawned],
  );

  const clearAll = useCallback(() => {
    for (const p of particules.current) {
      Composite.remove(engine.world, p.body);
    }
    particules.current = [];
    dead_particules.current = [];
  }, [engine]);

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

        // Сырой collisionStart бьёт чаще урона (конечность о конечность) —
        // без паузы на серии ударов мир забивается кругляшами и FPS падает.
        const now =
          typeof performance !== "undefined" ? performance.now() : Date.now();
        if (now - lastSpawnAt.current < BLOODY_SPAWN_GAP_MS) return;

        const contact = pair.collision.supports.at(0);
        if (!contact) return;
        if ([pair.bodyA, pair.bodyB].every(isSaveBody)) return;

        const result = computeDamage(pair.bodyA, pair.bodyB);
        if (result.damageA <= 0 && result.damageB <= 0) return;

        const parties = resolveHitParties(
          result,
          compositeA,
          compositeB,
          config,
        );
        if (!parties.length) return;

        const main = parties.reduce((a, b) =>
          b.victimDamage > a.victimDamage ? b : a,
        );

        const impactVelocity = Vector.magnitude(pair.collision.penetration) * 2;
        const rel = Vector.sub(pair.bodyA.velocity, pair.bodyB.velocity);
        // Выброс в сторону жертвы (away from aggressor velocity).
        const towardVictim =
          main.victimCompositeId === compositeA
            ? Vector.sub(pair.bodyA.position, pair.bodyB.position)
            : Vector.sub(pair.bodyB.position, pair.bodyA.position);
        const dir =
          Vector.magnitude(towardVictim) > 1
            ? towardVictim
            : Vector.magnitude(rel) > 0.5
              ? rel
              : pair.collision.penetration;

        lastSpawnAt.current = now;
        const spawned = spawnBloodyParticles(
          event.source.world,
          contact.x,
          contact.y,
          main.victimColors.main,
          {
            count: particleCountForImpact(main.victimDamage, impactVelocity),
            speed: 7 + Math.min(8, main.victimDamage * 0.05),
            dirX: dir.x,
            dirY: dir.y,
            alive: particules.current.length,
          },
        );
        pushSpawned(spawned);
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

  return { spawnAt, clearAll };
}
