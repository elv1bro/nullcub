import { isDebugMode } from "@/lib/debugMode";
import type { AbilityCooldownView } from "@/lib/usePlayerAbilities";
import type { FighterSide } from "@/lib/useHealth";
import type { ControlBindings } from "@/settings/SettingsContext";
import { useSettings } from "@/settings/SettingsContext";
import { formatKeyLabel } from "@/input/PlayerMovementInput";
import { AbilityBar } from "@/components/AbilityBar";

interface Props {
  battleOver: boolean;
  /** Скрыть HUD когда показывается recap (не сразу при battleOver). */
  showRecap: boolean;
  winner: FighterSide | null;
  faceReady: boolean;
  faceError: string | null;
  abilities: AbilityCooldownView;
  local2p?: boolean;
  opponentAbilities?: AbilityCooldownView;
  controlsP2?: ControlBindings;
}

function formatMoveHint(c: ControlBindings): string {
  return `${formatKeyLabel(c.up)}${formatKeyLabel(c.left)}${formatKeyLabel(c.down)}${formatKeyLabel(c.right)}`;
}

export function HpOverlay({
  battleOver,
  showRecap,
  winner,
  faceReady,
  faceError,
  abilities,
  local2p = false,
  opponentAbilities,
  controlsP2,
}: Props) {
  const { t, settings } = useSettings();
  const playerWon = battleOver && winner === "player";

  if (showRecap) return null;

  return (
    <div className="pointer-events-none fixed inset-0 z-10 p-4 flex flex-col justify-end items-center gap-3">
      {local2p && opponentAbilities ? (
        <div className="flex flex-col lg:flex-row items-end justify-center gap-4 w-full max-w-5xl">
          <div className="flex flex-col items-center gap-1 flex-1">
            <span className="text-[10px] font-ui uppercase tracking-widest text-cyan-300/80">
              {t.battle.player1}
            </span>
            <AbilityBar {...abilities} />
            <p className="text-xs text-gray-400 bg-black/30 inline-block px-2 py-1 rounded">
              {t.battle.controlsHint} {formatMoveHint(settings.controls)}
            </p>
          </div>
          <div className="flex flex-col items-center gap-1 flex-1">
            <span className="text-[10px] font-ui uppercase tracking-widest text-rose-300/80">
              {t.battle.player2}
            </span>
            <AbilityBar
              {...opponentAbilities}
              bindings={settings.abilitiesP2}
            />
            <p className="text-xs text-gray-400 bg-black/30 inline-block px-2 py-1 rounded">
              {t.battle.controlsHint}{" "}
              {formatMoveHint(controlsP2 ?? settings.controlsP2)}
            </p>
          </div>
        </div>
      ) : (
        <>
          <AbilityBar {...abilities} />
          <div className="text-center space-y-2">
            <p className="text-xs text-gray-400 bg-black/30 inline-block px-2 py-1 rounded">
              {t.battle.controlsHint}{" "}
              {formatMoveHint(settings.controls)}
              {isDebugMode() && t.battle.debugHint}
            </p>
            {faceError && (
              <p className="text-xs text-yellow-300 bg-black/40 inline-block px-2 py-1 rounded">
                {t.battle.webcamOff}
              </p>
            )}
            {faceReady && !faceError && !playerWon && (
              <p className="text-xs text-green-300/80 bg-black/30 inline-block px-2 py-1 rounded">
                {t.battle.webcamOn}
              </p>
            )}
          </div>
        </>
      )}
    </div>
  );
}
