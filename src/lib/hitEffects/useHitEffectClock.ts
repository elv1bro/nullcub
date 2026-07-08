import { useEngineEvent } from "@1.framework/matter4react";
import { useEngine } from "@1.framework/matter4react";
import { useEffect, type RefObject } from "react";
import type { HitEffectStore } from "./store";

function activeTimeScale(store: HitEffectStore, now: number): number {
  for (let i = store.timeSegments.length - 1; i >= 0; i--) {
    const seg = store.timeSegments[i]!;
    if (now >= seg.start && now < seg.until) return seg.scale;
  }
  return 1;
}

/** Применяет hit-stop и slow-mo через engine.timing.timeScale (#3, #10). */
export function useHitEffectClock(storeRef: RefObject<HitEffectStore>): void {
  const engine = useEngine();

  useEngineEvent(
    "beforeUpdate",
    () => {
      const store = storeRef.current;
      if (!store) return;
      engine.timing.timeScale = activeTimeScale(store, performance.now());
    },
    [engine, storeRef],
  );

  useEffect(() => {
    return () => {
      engine.timing.timeScale = 1;
    };
  }, [engine]);
}
