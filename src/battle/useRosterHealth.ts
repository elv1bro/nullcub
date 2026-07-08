import { useStickmanCollision } from "@/lib/useStickmanCollision";
import {
  computeDamage,
  FIGHTER_HIT_COOLDOWN_MS,
} from "@/lib/combat";
import { filterGrabDamage } from "@/lib/grab/rules";
import { filterDamageFromDeadAggressors } from "@/lib/combatActive";
import { isSaveBody } from "@/lib/isSaveBody";
import { isBattleSpawnGrace } from "@/lib/combatGrace";
import type { FighterRuntime } from "./types";
import { areEnemies } from "./types";
import type { Composite } from "matter-js";
import { useCallback, useRef, useState, type RefObject } from "react";

export function useRosterHealth(
  fighters: FighterRuntime[],
  composites: Composite[],
  battleStartRef: RefObject<number>,
  battleOverRef: RefObject<boolean>,
): {
  fighters: FighterRuntime[];
  setHp: (id: string, hp: number) => void;
  battleOver: boolean;
  winnerId: string | null;
} {
  const [hpMap, setHpMap] = useState<Record<string, number>>(() =>
    Object.fromEntries(fighters.map((f) => [f.id, f.maxHp])),
  );
  const hpRef = useRef(hpMap);
  hpRef.current = hpMap;
  const cooldown = useRef(new Map<string, number>());

  const fighterByComposite = useCallback(
    (compositeId: number): FighterRuntime | undefined =>
      fighters.find((f) => f.composite.id === compositeId),
    [fighters],
  );

  const applyHp = useCallback((id: string, next: number) => {
    hpRef.current = { ...hpRef.current, [id]: Math.max(0, next) };
    setHpMap({ ...hpRef.current });
  }, []);

  useStickmanCollision(
    composites,
    {
      onCollisionStart: (_event, { pair, compositeA, compositeB }) => {
        if (battleOverRef.current) return;
        const fa = fighterByComposite(compositeA);
        const fb = fighterByComposite(compositeB);
        if (!fa || !fb) return;
        if (!areEnemies(fa, fb)) return;

        const now = performance.now();
        if (isBattleSpawnGrace(battleStartRef.current ?? 0, now)) return;

        const { bodyA, bodyB } = pair;
        if ([bodyA, bodyB].every(isSaveBody)) return;

        const key = `${Math.min(compositeA, compositeB)}-${Math.max(compositeA, compositeB)}`;
        if ((cooldown.current.get(key) ?? 0) > now) return;

        const raw = computeDamage(bodyA, bodyB);
        const filtered = filterGrabDamage(compositeA, compositeB, raw, {
          playerCompositeId: fa.composite.id,
          opponentCompositeId: fb.composite.id,
          playerGrab: fa.grab ?? null,
          opponentGrab: fb.grab ?? null,
        });

        const tradeOpts = {
          battleOver: battleOverRef.current ?? false,
          playerHp: hpRef.current[fa.id] ?? 0,
          opponentHp: hpRef.current[fb.id] ?? 0,
          playerCompositeId: fa.composite.id,
          opponentCompositeId: fb.composite.id,
        };
        const result = filterDamageFromDeadAggressors(
          compositeA,
          compositeB,
          filtered.damageA,
          filtered.damageB,
          tradeOpts,
        );
        if (result.damageA <= 0 && result.damageB <= 0) return;

        cooldown.current.set(key, now + FIGHTER_HIT_COOLDOWN_MS);
        applyHp(fa.id, (hpRef.current[fa.id] ?? 0) - result.damageA);
        applyHp(fb.id, (hpRef.current[fb.id] ?? 0) - result.damageB);
      },
    },
    [fighters, composites, fighterByComposite, applyHp, battleStartRef, battleOverRef],
  );

  const merged = fighters.map((f) => ({
    ...f,
    hp: hpMap[f.id] ?? f.maxHp,
  }));

  const alive = merged.filter((f) => f.hp > 0);
  const battleOver = alive.length <= 1 && merged.some((f) => f.hp <= 0);
  const winnerId = battleOver ? (alive[0]?.id ?? null) : null;

  return {
    fighters: merged,
    setHp: applyHp,
    battleOver,
    winnerId,
  };
}
