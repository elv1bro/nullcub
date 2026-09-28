import { isDebugMode } from "@/lib/debugMode";
import type { AbilityCooldownView } from "@/lib/usePlayerAbilities";
import type { FighterSide } from "@/lib/useHealth";
import type { HitEffectStore } from "@/lib/hitEffects";
import type { AbilityBindings, ControlBindings } from "@/settings/SettingsContext";
import { useSettings } from "@/settings/SettingsContext";
import { formatKeyLabel } from "@/input/PlayerMovementInput";
import { AbilityBar } from "@/components/AbilityBar";
import {
  useEffect,
  useRef,
  useState,
  type RefObject,
} from "react";

export interface FighterAbilityHud {
  id: string;
  label: string;
  abilities: AbilityCooldownView;
  bindings?: AbilityBindings;
  moveHint: string;
  hp?: number;
  maxHp?: number;
  color?: string;
}

/** Статус бойца для верхней рамки (Dota / AAA glanceable). */
export interface BattleFighterStatus {
  name: string;
  hp: number;
  maxHp: number;
  color: string;
  secondaryColor?: string;
}

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
  /** N локальных бойцов (override local2p layout). */
  fighterBars?: FighterAbilityHud[];
  playerStatus?: BattleFighterStatus | null;
  opponentStatus?: BattleFighterStatus | null;
  /** Для комбо-чипа у таймера. */
  hitEffectsStoreRef?: RefObject<HitEffectStore | null>;
  lastHit?: FighterSide | null;
}

function formatMoveHint(c: ControlBindings): string {
  return `${formatKeyLabel(c.up)}${formatKeyLabel(c.left)}${formatKeyLabel(c.down)}${formatKeyLabel(c.right)}`;
}

function clampRatio(hp: number, maxHp: number): number {
  if (maxHp <= 0) return 0;
  return Math.max(0, Math.min(1, hp / maxHp));
}

/** Белый «хвост» урона — как в файтингах / Dota. */
function useLagRatio(hp: number, maxHp: number): number {
  const live = clampRatio(hp, maxHp);
  const [trail, setTrail] = useState(live);
  const liveRef = useRef(live);
  liveRef.current = live;

  useEffect(() => {
    if (live >= trail - 0.001) {
      if (live !== trail) setTrail(live);
      return undefined;
    }
    let drainId = 0;
    const delay = window.setTimeout(() => {
      drainId = window.setInterval(() => {
        setTrail((prev) => {
          const target = liveRef.current;
          if (prev <= target + 0.004) {
            window.clearInterval(drainId);
            return target;
          }
          return prev + (target - prev) * 0.16;
        });
      }, 33);
    }, 260);
    return () => {
      window.clearTimeout(delay);
      if (drainId) window.clearInterval(drainId);
    };
  }, [live]); // trail catch-up is self-driven

  return Math.max(live, trail);
}

function useHitFlash(hp: number): boolean {
  const prev = useRef(hp);
  const [flash, setFlash] = useState(false);
  useEffect(() => {
    if (hp < prev.current - 0.5) {
      setFlash(true);
      const t = window.setTimeout(() => setFlash(false), 320);
      prev.current = hp;
      return () => window.clearTimeout(t);
    }
    prev.current = hp;
    return undefined;
  }, [hp]);
  return flash;
}

function HpBar({
  status,
  align,
  danger,
}: {
  status: BattleFighterStatus;
  align: "left" | "right";
  danger?: boolean;
}) {
  const ratio = clampRatio(status.hp, status.maxHp);
  const lag = useLagRatio(status.hp, status.maxHp);
  const hitFlash = useHitFlash(status.hp);
  const hpShow = Math.max(0, Math.ceil(status.hp));
  const low = ratio <= 0.28;
  const crit = ratio <= 0.12;

  return (
    <div
      className={[
        "battle-frame__side",
        `battle-frame__side--${align}`,
        low || danger ? "is-low" : "",
        crit ? "is-crit" : "",
        hitFlash ? "is-hit" : "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <div
        className="battle-frame__portrait"
        style={{
          background: `linear-gradient(145deg, ${status.color}, ${status.secondaryColor ?? status.color})`,
          ["--p" as string]: status.color,
        }}
        aria-hidden
      >
        <span className="battle-frame__portrait-shine" />
      </div>
      <div className="battle-frame__meta">
        <div className="battle-frame__row">
          <span className="battle-frame__name font-display">{status.name}</span>
          <span className="battle-frame__hp font-ui tabular-nums">
            {hpShow}
            <span className="battle-frame__hp-max">/{Math.ceil(status.maxHp)}</span>
          </span>
        </div>
        <div
          className="battle-frame__bar"
          role="meter"
          aria-valuenow={hpShow}
          aria-valuemin={0}
          aria-valuemax={Math.ceil(status.maxHp)}
        >
          <div
            className="battle-frame__bar-trail"
            style={{ width: `${lag * 100}%` }}
          />
          <div
            className="battle-frame__bar-fill"
            style={{
              width: `${ratio * 100}%`,
              background: `linear-gradient(90deg, ${status.secondaryColor ?? status.color}, ${status.color})`,
            }}
          />
          <div className="battle-frame__bar-segments" aria-hidden />
          <div
            className="battle-frame__bar-glow"
            style={{ width: `${ratio * 100}%` }}
          />
        </div>
        {hitFlash && (
          <span className="battle-frame__dmg font-display" aria-hidden>
            HIT
          </span>
        )}
      </div>
    </div>
  );
}

function statusFromBar(bar: FighterAbilityHud, fallbackColor: string): BattleFighterStatus {
  const maxHp = bar.maxHp ?? 1000;
  return {
    name: bar.label,
    hp: bar.hp ?? maxHp,
    maxHp,
    color: bar.color ?? fallbackColor,
  };
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
  fighterBars,
  playerStatus,
  opponentStatus,
  hitEffectsStoreRef,
  lastHit,
}: Props) {
  const { t, settings } = useSettings();
  const playerWon = battleOver && winner === "player";
  const [combo, setCombo] = useState(0);

  useEffect(() => {
    if (!hitEffectsStoreRef) return undefined;
    const id = window.setInterval(() => {
      const c = hitEffectsStoreRef.current?.combo;
      const now = performance.now();
      if (c && c.count >= 2 && now - c.lastHitAt < 1000) {
        setCombo(c.count);
      } else {
        setCombo(0);
      }
    }, 80);
    return () => window.clearInterval(id);
  }, [hitEffectsStoreRef]);

  if (showRecap) return null;

  const showTopFrame = Boolean(
    playerStatus || opponentStatus || (fighterBars && fighterBars.length > 0),
  );

  const leftStatus =
    playerStatus ??
    (fighterBars?.[0] ? statusFromBar(fighterBars[0], "#38bdf8") : null);
  const rightStatus =
    opponentStatus ??
    (fighterBars?.[1] ? statusFromBar(fighterBars[1], "#f87171") : null);

  return (
    <div
      className={[
        "battle-hud",
        "pointer-events-none",
        "fixed",
        "inset-0",
        "z-10",
        lastHit === "player" ? "battle-hud--hit-left" : "",
        lastHit === "opponent" ? "battle-hud--hit-right" : "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <div className="battle-hud__vignette" aria-hidden />

      {showTopFrame && (
        <div className="battle-frame">
          {fighterBars && fighterBars.length > 2 ? (
            <div className="battle-frame__multi">
              {fighterBars.map((bar) => (
                <HpBar
                  key={bar.id}
                  align="left"
                  status={statusFromBar(bar, "#38bdf8")}
                />
              ))}
            </div>
          ) : (
            <>
              {leftStatus ? (
                <HpBar
                  status={leftStatus}
                  align="left"
                  danger={battleOver && winner === "opponent"}
                />
              ) : (
                <div className="battle-frame__side battle-frame__side--left" />
              )}
              <div className="battle-frame__center-spacer" aria-hidden>
                <div className="battle-frame__vs font-display">VS</div>
                {combo >= 2 && (
                  <div className="battle-frame__combo font-display" key={combo}>
                    ×{combo}
                  </div>
                )}
              </div>
              {rightStatus ? (
                <HpBar
                  status={rightStatus}
                  align="right"
                  danger={battleOver && winner === "player"}
                />
              ) : (
                <div className="battle-frame__side battle-frame__side--right" />
              )}
            </>
          )}
        </div>
      )}

      <div className="battle-hud__dock">
        {fighterBars && fighterBars.length > 0 ? (
          <div
            className={`battle-hud__ability-row ${
              fighterBars.length > 2 ? "battle-hud__ability-row--wide" : ""
            }`}
          >
            {fighterBars.map((bar) => (
              <div key={bar.id} className="battle-hud__fighter-col">
                <span className="battle-hud__fighter-label font-ui">{bar.label}</span>
                <AbilityBar {...bar.abilities} bindings={bar.bindings} />
                <p className="battle-hud__hint">
                  {t.battle.controlsHint} {bar.moveHint}
                </p>
              </div>
            ))}
          </div>
        ) : local2p && opponentAbilities ? (
          <div className="battle-hud__ability-row">
            <div className="battle-hud__fighter-col">
              <span className="battle-hud__fighter-label font-ui">{t.battle.player1}</span>
              <AbilityBar {...abilities} />
              <p className="battle-hud__hint">
                {t.battle.controlsHint} {formatMoveHint(settings.controls)}
              </p>
            </div>
            <div className="battle-hud__fighter-col">
              <span className="battle-hud__fighter-label font-ui">{t.battle.player2}</span>
              <AbilityBar
                {...opponentAbilities}
                bindings={settings.abilitiesP2}
              />
              <p className="battle-hud__hint">
                {t.battle.controlsHint}{" "}
                {formatMoveHint(controlsP2 ?? settings.controlsP2)}
              </p>
            </div>
          </div>
        ) : (
          <>
            <div className="battle-hud__skill-tray">
              <div className="battle-hud__skill-tray-edge" aria-hidden />
              <AbilityBar {...abilities} />
              <div className="battle-hud__skill-tray-edge battle-hud__skill-tray-edge--right" aria-hidden />
            </div>
            <div className="battle-hud__hints">
              <p className="battle-hud__hint">
                {t.battle.controlsHint} {formatMoveHint(settings.controls)}
                {isDebugMode() && t.battle.debugHint}
              </p>
              {faceError && (
                <p className="battle-hud__hint battle-hud__hint--warn">
                  {t.battle.webcamOff}
                </p>
              )}
              {faceReady && !faceError && !playerWon && (
                <p className="battle-hud__hint battle-hud__hint--ok">
                  {t.battle.webcamOn}
                </p>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
