import type { AiDifficultyId } from "@/battle/aiProfiles";
import {
  QUICK_OPPONENT_HP_DEFAULT,
  QUICK_OPPONENT_HP_OPTIONS,
  type QuickOpponentHp,
} from "@/lib/battleConfig";
import type { TeamSlot } from "@/team/teamSlots";
import { useTranslation } from "@/settings/SettingsContext";

export type LobbyMode = "vs" | "campaign" | "roguelike";

export interface LobbyScreenProps {
  slots: TeamSlot[];
  onAddLocal: () => void;
  onInvite: (slotIndex: number) => void;
  onRemove: (slotIndex: number) => void;
  mode: LobbyMode;
  onModeChange: (mode: LobbyMode) => void;
  botDifficulty: AiDifficultyId;
  onBotDifficultyChange?: (d: AiDifficultyId) => void;
  /** HP бота в режиме «против бота». */
  opponentHp?: QuickOpponentHp;
  onOpponentHpChange?: (hp: QuickOpponentHp) => void;
  onStart: () => void;
  canStart: boolean;
  /** На телефоне локальных добавить нельзя. */
  allowLocal?: boolean;
  /** Уже занято локальными (включая you). */
  localCount?: number;
  maxLocal?: number;
  /** Онлайн-инвайт доступен. */
  inviteEnabled?: boolean;
  inviteUrl?: string | null;
  inviteCode?: string | null;
  onCopyInvite?: () => void;
  inviteCopied?: boolean;
  onlinePlayers?: number;
  /** Онлайн-комната: гости жмут Ready, хост — Start. */
  isOnline?: boolean;
  isHost?: boolean;
  myReady?: boolean;
  onToggleReady?: () => void;
}

const LOBBY_MODES: LobbyMode[] = ["vs", "campaign", "roguelike"];
const DIFFICULTIES: AiDifficultyId[] = ["easy", "normal", "hard", "boss"];

/**
 * Пати-лобби: собрать группу (локал на ПК / инвайт) + режим + старт.
 * Режим «vs» — стандартный 1v1 против бота (только выбор HP).
 */
export function LobbyScreen({
  slots,
  onAddLocal,
  onInvite,
  onRemove,
  mode,
  onModeChange,
  botDifficulty,
  onBotDifficultyChange,
  opponentHp = QUICK_OPPONENT_HP_DEFAULT,
  onOpponentHpChange,
  onStart,
  canStart,
  allowLocal = true,
  localCount = 1,
  maxLocal = 2,
  inviteEnabled = false,
  inviteUrl = null,
  inviteCode = null,
  onCopyInvite,
  inviteCopied = false,
  onlinePlayers = 0,
  isOnline = false,
  isHost = true,
  myReady = false,
  onToggleReady,
}: LobbyScreenProps) {
  const t = useTranslation();
  const padded = padSlots(slots);
  const localFull = localCount >= maxLocal;
  const soloBot = mode === "vs";

  return (
    <div className="lobby-screen lobby-screen--party">
      <header className="lobby-screen__header">
        <h2 className="lobby-screen__title font-display">{t.lobby.title}</h2>
        <p className="lobby-screen__hint font-hand">
          {soloBot ? t.lobby.vsHint : t.lobby.partyHint}
        </p>
      </header>

      <section className="lobby-party">
        <div className="lobby-party__modes" role="tablist" aria-label={t.lobby.modeTitle}>
          {LOBBY_MODES.map((m) => (
            <button
              key={m}
              type="button"
              role="tab"
              aria-selected={mode === m}
              className={
                mode === m
                  ? m === "roguelike"
                    ? "lobby-mode lobby-mode--active lobby-mode--wip"
                    : "lobby-mode lobby-mode--active"
                  : m === "roguelike"
                    ? "lobby-mode lobby-mode--wip"
                    : "lobby-mode"
              }
              onClick={() => onModeChange(m)}
            >
              <span>{t.lobby.mode[m]}</span>
              {m === "roguelike" && (
                <span className="lobby-mode__wip font-ui">{t.lobby.wipBadge}</span>
              )}
            </button>
          ))}
        </div>

        {soloBot && (
          <div className="lobby-hp" role="group" aria-label={t.lobby.opponentHp}>
            <span className="lobby-hp__label font-ui">{t.lobby.opponentHp}</span>
            <div className="lobby-hp__chips">
              {QUICK_OPPONENT_HP_OPTIONS.map((hp) => {
                const active = hp === opponentHp;
                const isDefault = hp === QUICK_OPPONENT_HP_DEFAULT;
                return (
                  <button
                    key={hp}
                    type="button"
                    className={
                      active
                        ? "lobby-hp__chip lobby-hp__chip--active"
                        : "lobby-hp__chip"
                    }
                    aria-pressed={active}
                    onClick={() => onOpponentHpChange?.(hp)}
                  >
                    <span className="lobby-hp__value">{hp}</span>
                    {isDefault && (
                      <span className="lobby-hp__tag font-ui">
                        {t.lobby.opponentHpStandard}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {mode === "roguelike" && (
          <p className="lobby-wip-plaque font-ui" role="status">
            {t.lobby.wipBadge}
            <span className="lobby-wip-plaque__text">{t.lobby.roguelikeWip}</span>
          </p>
        )}

        {mode === "roguelike" && onBotDifficultyChange && (
          <label className="lobby-screen__diff font-ui">
            <span>{t.lobby.botDifficulty}</span>
            <select
              value={botDifficulty}
              onChange={(e) =>
                onBotDifficultyChange(e.target.value as AiDifficultyId)
              }
            >
              {DIFFICULTIES.map((d) => (
                <option key={d} value={d}>
                  {t.lobby.difficulty[d]}
                </option>
              ))}
            </select>
          </label>
        )}

        {!soloBot && (
          <>
            <div className="lobby-party__slots">
              {padded.map((slot, index) => (
                <div
                  key={index}
                  className={`lobby-seat lobby-seat--${slot.kind}`}
                  data-kind={slot.kind}
                  data-slot={index}
                >
                  <span className="lobby-seat__badge font-ui">
                    {t.lobby.slotLabel.replace("{n}", String(index + 1))}
                  </span>
                  {slot.kind === "you" && (
                    <>
                      <div className="lobby-seat__face lobby-seat__face--you" aria-hidden />
                      <span className="lobby-seat__name font-display">
                        {slot.name || t.lobby.you}
                      </span>
                      <span className="lobby-seat__role font-ui">{t.lobby.host}</span>
                    </>
                  )}
                  {slot.kind === "local" && (
                    <>
                      <div className="lobby-seat__face lobby-seat__face--local" aria-hidden />
                      <span className="lobby-seat__name font-display">{slot.name}</span>
                      <span className="lobby-seat__role font-ui">{t.lobby.localTag}</span>
                      <button
                        type="button"
                        className="lobby-seat__remove"
                        onClick={() => onRemove(index)}
                      >
                        {t.lobby.remove}
                      </button>
                    </>
                  )}
                  {slot.kind === "remote" && (
                    <>
                      <div className="lobby-seat__face lobby-seat__face--remote" aria-hidden />
                      <span className="lobby-seat__name font-display">{slot.name}</span>
                      <span className="lobby-seat__role font-ui">{t.lobby.onlineTag}</span>
                      <button
                        type="button"
                        className="lobby-seat__remove"
                        onClick={() => onRemove(index)}
                      >
                        {t.lobby.remove}
                      </button>
                    </>
                  )}
                  {slot.kind === "empty" && (
                    <>
                      <span className="lobby-seat__empty font-ui">{t.lobby.empty}</span>
                      <div className="lobby-seat__actions">
                        {allowLocal && !localFull ? (
                          <button
                            type="button"
                            className="lobby-seat__btn lobby-seat__btn--local"
                            onClick={onAddLocal}
                          >
                            {t.lobby.addLocal}
                          </button>
                        ) : (
                          <button
                            type="button"
                            className="lobby-seat__btn lobby-seat__btn--local"
                            disabled
                            title={
                              !allowLocal
                                ? t.lobby.localPhoneBlocked
                                : t.lobby.localFull
                            }
                          >
                            {t.lobby.addLocal}
                          </button>
                        )}
                        <button
                          type="button"
                          className="lobby-seat__btn lobby-seat__btn--invite"
                          disabled={!inviteEnabled}
                          onClick={() => onInvite(index)}
                          title={
                            inviteEnabled ? undefined : t.lobby.inviteUnavailable
                          }
                        >
                          {t.lobby.invite}
                        </button>
                      </div>
                    </>
                  )}
                </div>
              ))}
            </div>

            {!allowLocal && (
              <p className="lobby-party__note font-ui">{t.lobby.localPhoneBlocked}</p>
            )}
            {allowLocal && (
              <p className="lobby-party__note font-ui">
                {t.lobby.localPcHint
                  .replace("{n}", String(Math.max(0, maxLocal - 1)))
                  .replace("{max}", String(maxLocal))}
              </p>
            )}

            {inviteEnabled && (
              <div className="lobby-invite">
                <p className="lobby-invite__title font-display">{t.lobby.invitePanel}</p>
                {inviteUrl || inviteCode ? (
                  <>
                    <code className="lobby-invite__code font-ui">
                      {inviteCode || inviteUrl}
                    </code>
                    {onCopyInvite && (
                      <button
                        type="button"
                        className="lobby-invite__copy"
                        onClick={onCopyInvite}
                      >
                        {inviteCopied ? t.lobby.inviteCopied : t.lobby.copyInvite}
                      </button>
                    )}
                    {onlinePlayers > 0 && (
                      <p className="lobby-invite__online font-ui">
                        {t.lobby.onlineCount.replace("{n}", String(onlinePlayers))}
                      </p>
                    )}
                  </>
                ) : (
                  <p className="lobby-invite__hint font-ui">{t.lobby.inviteHint}</p>
                )}
              </div>
            )}
          </>
        )}
      </section>

      <footer className="lobby-screen__footer">
        {isOnline && !isHost && onToggleReady ? (
          <button
            type="button"
            className={
              myReady
                ? "lobby-screen__start lobby-screen__start--ready"
                : "lobby-screen__start"
            }
            onClick={onToggleReady}
          >
            {myReady ? t.lobby.readyOn : t.lobby.readyOff}
          </button>
        ) : (
          <button
            type="button"
            className="lobby-screen__start"
            disabled={!canStart}
            onClick={onStart}
          >
            {t.lobby.start}
          </button>
        )}
      </footer>
    </div>
  );
}

function padSlots(slots: TeamSlot[]): TeamSlot[] {
  const out = slots.slice(0, 4);
  while (out.length < 4) out.push({ kind: "empty" });
  return out;
}
