import { useEffect, useRef, useState, type RefObject } from "react";
import {
  BATTLE_TIME_LIMIT_MS,
  suddenDeathMultiplier,
} from "@/lib/battleTuning";
import { useSettings } from "@/settings/SettingsContext";

interface Props {
  /** performance.now() старта боя; 0 — бой ещё не начался. */
  startRef: RefObject<number>;
  battleOver: boolean;
  /** Скрыть после задержки recap (до этого — замороженный таймер). */
  showRecap: boolean;
}

/** Таймер в центре верхней рамки боя. */
export function BattleTimer({ startRef, battleOver, showRecap }: Props) {
  const { t } = useSettings();
  const [now, setNow] = useState(() => performance.now());
  const frozenAtRef = useRef<number | null>(null);

  useEffect(() => {
    if (battleOver) {
      frozenAtRef.current = performance.now();
      return undefined;
    }
    frozenAtRef.current = null;
    const id = setInterval(() => setNow(performance.now()), 250);
    return () => clearInterval(id);
  }, [battleOver]);

  const start = startRef.current ?? 0;
  if (!start || showRecap) return null;

  const clockNow = battleOver ? (frozenAtRef.current ?? now) : now;
  const elapsed = clockNow - start;
  const leftMs = Math.max(0, BATTLE_TIME_LIMIT_MS - elapsed);

  if (leftMs <= 0) {
    const mult = suddenDeathMultiplier(elapsed);
    return (
      <div className="battle-clock pointer-events-none">
        <div className="battle-clock__badge battle-clock__badge--death font-ui">
          {t.battle.suddenDeath}
          <span className="battle-clock__mult">×{mult.toFixed(2)}</span>
        </div>
      </div>
    );
  }

  const totalSec = Math.ceil(leftMs / 1000);
  const mm = Math.floor(totalSec / 60);
  const ss = String(totalSec % 60).padStart(2, "0");
  const urgent = totalSec <= 10;

  return (
    <div className="battle-clock pointer-events-none">
      <div
        className={`battle-clock__badge font-display tabular-nums ${
          urgent ? "battle-clock__badge--urgent" : ""
        }`}
      >
        {mm}:{ss}
      </div>
    </div>
  );
}
