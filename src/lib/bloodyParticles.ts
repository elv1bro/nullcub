import { Particle } from "@/lib/Particle";
import { Body, Common, Composite, type World } from "matter-js";

/** Жёсткий потолок живых кругляшей: выше — Matter + Render начинают душить кадр. */
export const BLOODY_MAX_ALIVE = 96;
/** Не чаще одного выброса на серию касаний конечностей. */
export const BLOODY_SPAWN_GAP_MS = 90;

export type BloodySpawnOpts = {
  count?: number;
  speed?: number;
  /** Направление удара (unit-ish); конус разлёта вокруг него. */
  dirX?: number;
  dirY?: number;
  /** Сколько уже живых — чтобы не превысить {@link BLOODY_MAX_ALIVE}. */
  alive?: number;
};

/** Кругляши-обломки (цвет жертвы) — live-коллизии и кинематический replay. */
export function spawnBloodyParticles(
  world: World,
  x: number,
  y: number,
  color: string,
  opts?: BloodySpawnOpts,
): Particle[] {
  const budget = Math.max(0, BLOODY_MAX_ALIVE - (opts?.alive ?? 0));
  if (budget <= 0) return [];

  const count = Math.max(1, Math.min(28, opts?.count ?? 16, budget));
  const speed = opts?.speed ?? 9;
  let dirX = opts?.dirX ?? 0;
  let dirY = opts?.dirY ?? 0;
  const dirLen = Math.hypot(dirX, dirY);
  const hasDir = dirLen > 0.08;
  if (hasDir) {
    dirX /= dirLen;
    dirY /= dirLen;
  }

  return Array.from({ length: count }, () => {
    const p = new Particle(x, y, 1.5 + Common.random(0, 2), color);
    Composite.add(world, p.body);
    let vx: number;
    let vy: number;
    if (hasDir) {
      // Основной выброс по вектору удара + боковой разброс.
      const along = speed * (0.55 + Common.random(0, 0.9));
      const side = speed * Common.random(-0.55, 0.55);
      vx = dirX * along - dirY * side;
      vy = dirY * along + dirX * side - speed * 0.15;
    } else {
      vx = Common.random(-speed, speed);
      vy = Common.random(-speed * 1.25, speed * 0.35);
    }
    Body.setVelocity(p.body, { x: vx, y: vy });
    return p;
  });
}

/**
 * Снимает самые старые кругляши, чтобы влезла новая пачка.
 * `list` — от новых к старым (новые prepend'ятся в начало).
 */
export function pruneBloodyParticles(
  world: World,
  list: Particle[],
  keep: number,
): Particle[] {
  if (list.length <= keep) return list;
  const drop = list.length - keep;
  for (let i = list.length - drop; i < list.length; i += 1) {
    const p = list[i];
    if (p) Composite.remove(world, p.body);
  }
  list.length = keep;
  return list;
}

export function particleCountForImpact(
  victimDamage: number,
  impactVelocity: number,
): number {
  return Math.min(
    28,
    Math.max(6, Math.floor(impactVelocity * victimDamage * 0.05)),
  );
}

export function particleCountForReplayDamage(damage: number): number {
  return Math.min(24, Math.max(8, Math.floor(6 + damage * 0.35)));
}
