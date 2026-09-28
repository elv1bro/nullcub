import { playResultSting, stopMusic } from "@/audio";
import type { BattleMomentsStore } from "@/lib/battleMoments";
import { MEDAL_BY_ID, type MedalId } from "@/lib/achievements";
import { useSettings } from "@/settings/SettingsContext";
import { GameContext } from "@/GameContext";
import { useCallback, useContext, useEffect, useState } from "react";

interface Props {
  battleOver: boolean;
  showRecap: boolean;
  winner: "player" | "opponent" | null;
  ourTeamName: string;
  enemyTeamName: string;
  moments: BattleMomentsStore;
  campaignOutro?: string | null;
  battleMedals?: MedalId[];
}

type LightboxSlide = {
  imageUrl: string;
  title: string;
  line1: string;
  line2?: string;
};

function PolaroidCard({
  title,
  line1,
  line2,
  imageUrl,
  tilt,
  zoomHint,
  onZoom,
}: {
  title: string;
  line1: string;
  line2?: string;
  imageUrl: string | null;
  tilt: string;
  zoomHint: string;
  onZoom?: (slide: LightboxSlide) => void;
}) {
  const canZoom = !!imageUrl && !!onZoom;

  return (
    <figure className={["battle-polaroid", tilt].join(" ")}>
      <div className="battle-polaroid-frame">
        {canZoom ? (
          <button
            type="button"
            className="battle-polaroid-photo-btn"
            onClick={() =>
              onZoom({ imageUrl: imageUrl!, title, line1, line2 })
            }
            aria-label={zoomHint}
          >
            <img
              src={imageUrl}
              alt=""
              className="battle-polaroid-photo"
              draggable={false}
            />
            <span className="battle-polaroid-zoom-hint">{zoomHint}</span>
          </button>
        ) : (
          <div className="battle-polaroid-photo-btn battle-polaroid-photo-btn--static">
            <div className="battle-polaroid-photo battle-polaroid-photo--pending" />
          </div>
        )}

        <figcaption className="battle-polaroid-caption">
          <p className="battle-polaroid-hand battle-polaroid-hand--title">
            {title}
          </p>
          <p className="battle-polaroid-hand">{line1}</p>
          {line2 && (
            <p className="battle-polaroid-hand battle-polaroid-hand--damage">
              {line2}
            </p>
          )}
        </figcaption>
      </div>
    </figure>
  );
}

function PolaroidLightbox({
  slide,
  closeLabel,
  onClose,
}: {
  slide: LightboxSlide;
  closeLabel: string;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="battle-polaroid-lightbox pointer-events-auto"
      role="dialog"
      aria-modal="true"
      onClick={onClose}
    >
      <button
        type="button"
        className="battle-polaroid-lightbox__close menu-nav-btn text-sm!"
        onClick={onClose}
      >
        {closeLabel}
      </button>
      <figure
        className="battle-polaroid-lightbox__card"
        onClick={(e) => e.stopPropagation()}
      >
        <img
          src={slide.imageUrl}
          alt=""
          className="battle-polaroid-lightbox__photo"
          draggable={false}
        />
        <figcaption className="battle-polaroid-caption battle-polaroid-caption--large">
          <p className="battle-polaroid-hand battle-polaroid-hand--title">
            {slide.title}
          </p>
          <p className="battle-polaroid-hand">{slide.line1}</p>
          {slide.line2 && (
            <p className="battle-polaroid-hand battle-polaroid-hand--damage">
              {slide.line2}
            </p>
          )}
        </figcaption>
      </figure>
    </div>
  );
}

export function BattleRecapOverlay({
  battleOver,
  showRecap,
  winner,
  ourTeamName,
  enemyTeamName,
  moments,
  campaignOutro,
  battleMedals = [],
}: Props) {
  const { t } = useSettings();
  const { sendN } = useContext(GameContext);
  const [lightbox, setLightbox] = useState<LightboxSlide | null>(null);
  const closeLightbox = useCallback(() => setLightbox(null), []);
  const playerWon = battleOver && winner === "player";
  // winner === null при battleOver — двойной нокаут (ничья); экран всё равно нужен.
  const isDraw = battleOver && winner === null;

  // Не глушим бой на KO — во время replay ещё играют музыка и удары.
  useEffect(() => {
    if (!battleOver || !showRecap) return;
    stopMusic(700);
    playResultSting(winner === "player" ? "victory" : "defeat");
  }, [battleOver, showRecap, winner]);

  if (!battleOver || !showRecap) return null;

  const dealtDamage = moments.teamDealt?.damageLabel;
  const receivedDamage = moments.teamReceived?.damageLabel;
  const knockoutLine1 = moments.knockout
    ? `${moments.knockout.winnerName} → ${moments.knockout.loserName}`
    : winner === "player"
      ? `${ourTeamName} → ${enemyTeamName}`
      : winner === "opponent"
        ? `${enemyTeamName} → ${ourTeamName}`
        : `${ourTeamName} ⇄ ${enemyTeamName}`;

  return (
    <div className="pointer-events-none fixed inset-0 z-30 flex flex-col battle-recap-root">
      <div className="battle-recap-vignette absolute inset-0" />

      <div className="relative flex flex-1 flex-col items-center justify-center px-3 py-6 gap-5 min-h-0">
        <div className="text-center space-y-1 shrink-0">
          <p
            className={[
              "font-display text-2xl sm:text-4xl tracking-wide",
              winner === "player"
                ? "text-cyan-300"
                : isDraw
                  ? "text-amber-300"
                  : "text-red-300",
            ].join(" ")}
          >
            {winner === "player"
              ? t.battle.victory
              : isDraw
                ? t.battle.draw
                : t.battle.defeat}
          </p>
          <p className="text-sm sm:text-base text-white/75 font-hand">
            {ourTeamName}
            <span className="mx-2 text-white/35">{t.battle.recapVs}</span>
            {enemyTeamName}
          </p>
          {playerWon && campaignOutro && (
            <p className="text-xs text-gray-300 max-w-md mx-auto leading-snug font-ui">
              {campaignOutro}
            </p>
          )}
          {playerWon && !campaignOutro && (
            <p className="text-xs text-gray-400 font-ui">{t.battle.victoryHint}</p>
          )}
          {isDraw && (
            <p className="text-xs text-amber-200/80 font-ui">
              {t.battle.drawHint}
            </p>
          )}
          {!playerWon && !isDraw && (
            <p className="text-xs text-amber-200/80 font-ui">
              {t.battle.defeatGhostHint}
            </p>
          )}
        </div>

        <div className="battle-polaroid-row pointer-events-auto">
          <PolaroidCard
            title={t.battle.recapDealt}
            line1={`${ourTeamName} → ${enemyTeamName}`}
            line2={dealtDamage ?? "—"}
            imageUrl={moments.teamDealt?.dataUrl ?? null}
            tilt="battle-polaroid--tilt-left"
            zoomHint={t.battle.recapZoomHint}
            onZoom={setLightbox}
          />
          <PolaroidCard
            title={t.battle.recapReceived}
            line1={`${enemyTeamName} → ${ourTeamName}`}
            line2={receivedDamage ?? "—"}
            imageUrl={moments.teamReceived?.dataUrl ?? null}
            tilt="battle-polaroid--tilt-center"
            zoomHint={t.battle.recapZoomHint}
            onZoom={setLightbox}
          />
          <PolaroidCard
            title={t.battle.recapKnockout}
            line1={knockoutLine1}
            imageUrl={moments.knockout?.dataUrl ?? null}
            tilt="battle-polaroid--tilt-right"
            zoomHint={t.battle.recapZoomHint}
            onZoom={setLightbox}
          />
        </div>

        {battleMedals.length > 0 && (
          <div className="battle-medals pointer-events-auto shrink-0">
            <p className="battle-medals__title font-ui text-xs uppercase tracking-wide text-white/55">
              {t.battle.recapMedals}
            </p>
            <ul className="battle-medals__row">
              {battleMedals.map((id) => {
                const medal = MEDAL_BY_ID[id];
                return (
                  <li key={id} className="battle-medal" title={t.medals[id]}>
                    <span className="battle-medal__icon" aria-hidden>
                      {medal.icon}
                    </span>
                    <span className="battle-medal__label font-hand text-sm">
                      {t.medals[id]}
                    </span>
                  </li>
                );
              })}
            </ul>
          </div>
        )}

        <button
          type="button"
          className="pointer-events-auto menu-nav-btn menu-nav-btn--primary px-10 text-sm! shrink-0"
          onClick={sendN("BACK")}
        >
          {t.battle.backToMenu}
        </button>
      </div>

      {lightbox && (
        <PolaroidLightbox
          slide={lightbox}
          closeLabel={t.battle.recapCloseZoom}
          onClose={closeLightbox}
        />
      )}
    </div>
  );
}
