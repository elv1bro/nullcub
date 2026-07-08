import { useEventBeforeUpdate } from "@1.framework/matter4react";
import type { FighterColors } from "@/lib/fighterColors";
import type { HitEffectStore } from "@/lib/hitEffects/store";
import { dispatchVictoryScatterEffects } from "@/lib/hitEffects/dispatch";
import { findHead, scatterKoRagdoll } from "@/lib/victoryKoScatter";
import type { FighterSide } from "@/lib/useHealth";
import Matter, { type Composite, type IEventTimestamped } from "matter-js";
import { useEffect, useRef, type RefObject } from "react";

type Options = {
  battleOver: boolean;
  winner: FighterSide | null;
  screenEffects: boolean;
  playerCompositeRef: RefObject<Composite | undefined>;
  opponentCompositeRef: RefObject<Composite | undefined>;
  hitEffectsStore: RefObject<HitEffectStore | null>;
  playerColors: FighterColors;
  opponentColors: FighterColors;
};

export function useVictoryDefeatFx({
  battleOver,
  winner,
  screenEffects,
  playerCompositeRef,
  opponentCompositeRef,
  hitEffectsStore,
  playerColors,
  opponentColors,
}: Options): void {
  const didRef = useRef(false);
  const pendingRef = useRef<{ composite: Composite; colors: FighterColors }[]>(
    [],
  );

  useEffect(() => {
    if (!battleOver || didRef.current) return;

    // winner === null при battleOver — ничья: разлетаются оба.
    const losers: {
      composite: Composite | null | undefined;
      colors: FighterColors;
    }[] =
      winner === "player"
        ? [{ composite: opponentCompositeRef.current, colors: opponentColors }]
        : winner === "opponent"
          ? [{ composite: playerCompositeRef.current, colors: playerColors }]
          : [
              { composite: playerCompositeRef.current, colors: playerColors },
              { composite: opponentCompositeRef.current, colors: opponentColors },
            ];

    const resolved = losers.filter(
      (l): l is { composite: Composite; colors: FighterColors } =>
        !!l.composite,
    );
    if (resolved.length === 0) return;

    didRef.current = true;
    pendingRef.current = resolved;
  }, [
    battleOver,
    winner,
    playerCompositeRef,
    opponentCompositeRef,
    playerColors,
    opponentColors,
  ]);

  useEventBeforeUpdate(
    (event: IEventTimestamped<Matter.Engine>) => {
      const pending = pendingRef.current;
      if (pending.length === 0) return;

      pendingRef.current = [];
      for (const { composite, colors } of pending) {
        scatterKoRagdoll(event.source, composite);

        const head = findHead(composite);
        const store = hitEffectsStore.current;
        if (head && store && screenEffects) {
          dispatchVictoryScatterEffects(
            store,
            head.position.x,
            head.position.y,
            colors.main,
            performance.now(),
          );
        }
      }
    },
    [hitEffectsStore, screenEffects],
  );
}
