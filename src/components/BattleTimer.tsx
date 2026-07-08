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

/** Таймер боя вверху экрана; после лимита — плашка sudden death. */
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
      <div className="pointer-events-none fixed top-3 left-1/2 -translate-x-1/2 z-10">
        <div className="font-ui uppercase tracking-widest text-rose-400 text-sm animate-pulse bg-black/50 px-3 py-1 rounded">
          {t.battle.suddenDeath} ×{mult.toFixed(2)}
        </div>
      </div>
    );
  }

  const totalSec = Math.ceil(leftMs / 1000);
  const mm = Math.floor(totalSec / 60);
  const ss = String(totalSec % 60).padStart(2, "0");
  const urgent = totalSec <= 10;

  return (
    <div className="pointer-events-none fixed top-3 left-1/2 -translate-x-1/2 z-10">
      <div
        className={`font-ui tracking-widest tabular-nums bg-black/40 px-3 py-1 rounded text-lg ${
          urgent ? "text-rose-300 animate-pulse" : "text-white/85"
        }`}
      >
        {mm}:{ss}
      </div>
    </div>
  );
}
