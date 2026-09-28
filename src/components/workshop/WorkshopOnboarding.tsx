import type { LocaleStrings } from "@/i18n/types";

type Props = {
  t: LocaleStrings["workshop"];
  starters: { id: string; name: string; parts: number }[];
  onDismiss: () => void;
  onLoadStarter: (id: string) => void;
  onSkip: () => void;
};

export function WorkshopOnboarding({
  t,
  starters,
  onDismiss,
  onLoadStarter,
  onSkip,
}: Props) {
  return (
    <div className="ws-onboarding" role="dialog" aria-modal="true">
      <div className="ws-onboarding__card">
        <h2 className="ws-onboarding__title">{t.onboardTitle}</h2>
        <ol className="ws-onboarding__steps">
          <li>{t.onboardStep1}</li>
          <li>{t.onboardStep2}</li>
          <li>{t.onboardStep3}</li>
        </ol>
        {starters.length > 0 && (
          <div className="ws-onboarding__starters">
            <p className="ws-onboarding__starters-label">{t.onboardLoadTemplate}</p>
            <div className="ws-onboarding__starter-row">
              {starters.slice(0, 4).map((s) => (
                <button
                  key={s.id}
                  type="button"
                  className="ws-onboarding__starter"
                  onClick={() => {
                    onLoadStarter(s.id);
                    onDismiss();
                  }}
                >
                  <span className="ws-onboarding__starter-name">{s.name}</span>
                  <span className="ws-onboarding__starter-meta">
                    {s.parts} pts
                  </span>
                </button>
              ))}
            </div>
          </div>
        )}
        <div className="ws-onboarding__actions">
          <button
            type="button"
            className="ws-action-btn ws-action-btn--fight ws-action-btn--text"
            onClick={onDismiss}
          >
            {t.onboardStartEmpty}
          </button>
          <button
            type="button"
            className="ws-action-btn ws-action-btn--ghost ws-action-btn--text"
            onClick={() => {
              onSkip();
              onDismiss();
            }}
          >
            {t.onboardSkip}
          </button>
        </div>
      </div>
    </div>
  );
}

export const WORKSHOP_ONBOARD_KEY = "ragdoll-workshop-onboarded";

export function hasSeenWorkshopOnboarding(): boolean {
  try {
    return localStorage.getItem(WORKSHOP_ONBOARD_KEY) === "1";
  } catch {
    return true;
  }
}

export function markWorkshopOnboardingSeen(): void {
  try {
    localStorage.setItem(WORKSHOP_ONBOARD_KEY, "1");
  } catch {
    /* ignore */
  }
}
