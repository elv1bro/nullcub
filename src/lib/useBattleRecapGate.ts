import { useCallback, useEffect, useState } from "react";
import { BATTLE_RECAP_DELAY_MS } from "./battleTuning";
import { getE2EScenario } from "@/dev/e2eHarness";

export type BattleEndPhase = "live" | "replay" | "recap";

/**
 * После KO: короткая пауза → повтор боя (если есть лента) → поляроиды.
 * В e2e сразу recap, чтобы verify не ждал повтор.
 */
export function useBattleEndPhases(
  battleOver: boolean,
  hasReplayTape: boolean,
): {
  phase: BattleEndPhase;
  showReplay: boolean;
  showRecap: boolean;
  goToRecap: () => void;
} {
  const [phase, setPhase] = useState<BattleEndPhase>("live");

  useEffect(() => {
    if (!battleOver) {
      setPhase("live");
      return undefined;
    }
    const skipReplay = Boolean(getE2EScenario()) || !hasReplayTape;
    const id = setTimeout(() => {
      setPhase(skipReplay ? "recap" : "replay");
    }, BATTLE_RECAP_DELAY_MS);
    return () => clearTimeout(id);
  }, [battleOver, hasReplayTape]);

  const goToRecap = useCallback(() => setPhase("recap"), []);

  return {
    phase,
    showReplay: phase === "replay",
    showRecap: phase === "recap",
    goToRecap,
  };
}

/** @deprecated используй useBattleEndPhases — оставлен для Dedicated/Guest. */
export function useBattleRecapGate(battleOver: boolean): boolean {
  const { showRecap } = useBattleEndPhases(battleOver, false);
  return showRecap;
}
