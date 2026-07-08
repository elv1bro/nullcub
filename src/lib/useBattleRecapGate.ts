import { useEffect, useState } from "react";
import { BATTLE_RECAP_DELAY_MS } from "./battleTuning";

/** Задержка recap после battleOver — HUD остаётся до showRecap. */
export function useBattleRecapGate(battleOver: boolean): boolean {
  const [showRecap, setShowRecap] = useState(false);

  useEffect(() => {
    if (!battleOver) {
      setShowRecap(false);
      return undefined;
    }
    const id = setTimeout(() => setShowRecap(true), BATTLE_RECAP_DELAY_MS);
    return () => clearTimeout(id);
  }, [battleOver]);

  return showRecap;
}
