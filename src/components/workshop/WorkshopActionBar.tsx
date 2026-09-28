import type { LocaleStrings } from "@/i18n/types";

type Props = {
  t: LocaleStrings["workshop"];
  workshopKind: "monster" | "item" | "arena";
  physicsPreview: boolean;
  fightReady: boolean;
  fightBlockedReason?: string;
  libraryOpen: boolean;
  onToggleLibrary: () => void;
  onTogglePhysics: () => void;
  onFight: () => void;
  onSave: () => void;
  onClear: () => void;
  onShare?: () => void;
  onImportShare?: () => void;
  onStress?: () => void;
};

export function WorkshopActionBar({
  t,
  workshopKind,
  physicsPreview,
  fightReady,
  fightBlockedReason,
  libraryOpen,
  onToggleLibrary,
  onTogglePhysics,
  onFight,
  onSave,
  onClear,
  onShare,
  onImportShare,
  onStress,
}: Props) {
  return (
    <div className="ws-action-bar ws-action-bar--labeled">
      <button
        type="button"
        className={[
          "ws-action-btn ws-action-btn--text",
          libraryOpen ? "ws-action-btn--active" : "",
        ].join(" ")}
        onClick={onToggleLibrary}
        title={t.library}
      >
        {t.library}
      </button>
      <button
        type="button"
        className={[
          "ws-action-btn ws-action-btn--text",
          physicsPreview ? "ws-action-btn--active" : "",
        ].join(" ")}
        onClick={onTogglePhysics}
        title={physicsPreview ? t.physicsStop : t.testMode}
      >
        {physicsPreview ? t.physicsStopShort : t.physicsStartShort}
      </button>
      {workshopKind === "monster" && onStress && (
        <button
          type="button"
          className="ws-action-btn ws-action-btn--text"
          onClick={onStress}
          disabled={physicsPreview}
          title={t.stressTest}
        >
          {t.stressShort}
        </button>
      )}
      {workshopKind === "monster" && (
        <button
          type="button"
          className="ws-action-btn ws-action-btn--fight ws-action-btn--text ws-action-btn--cta"
          onClick={onFight}
          disabled={physicsPreview || !fightReady}
          title={
            !fightReady
              ? fightBlockedReason || t.notReadyToFight
              : t.fight
          }
        >
          {t.fight}
        </button>
      )}
      <button
        type="button"
        className="ws-action-btn ws-action-btn--text"
        onClick={onSave}
        disabled={physicsPreview}
        title={t.save}
      >
        {t.save}
      </button>
      {workshopKind === "monster" && onShare && (
        <button
          type="button"
          className="ws-action-btn ws-action-btn--text"
          onClick={onShare}
          disabled={physicsPreview || !fightReady}
          title={t.shareMonster}
        >
          {t.shareShort}
        </button>
      )}
      {workshopKind === "monster" && onImportShare && (
        <button
          type="button"
          className="ws-action-btn ws-action-btn--ghost ws-action-btn--text"
          onClick={onImportShare}
          disabled={physicsPreview}
          title={t.importMonster}
        >
          {t.importShort}
        </button>
      )}
      <button
        type="button"
        className="ws-action-btn ws-action-btn--ghost ws-action-btn--text"
        onClick={onClear}
        disabled={physicsPreview}
        title={t.clear}
      >
        {t.clear}
      </button>
    </div>
  );
}
