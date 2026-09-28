import { useViewportFlags } from "@/hooks/useViewportFlags";
import { useSettings } from "@/settings/SettingsContext";
import { useEffect, useState } from "react";

const DISMISS_KEY = "ragdoll.landscapeHint.dismissed";

/**
 * На телефоне в портрете просим альбом: ширина экрана > высоты.
 * Можно «всё равно» — на сессию; после поворота подсказка сама уходит.
 */
export function LandscapeHint() {
  const { t } = useSettings();
  const { portrait, coarse } = useViewportFlags();
  const [dismissed, setDismissed] = useState(() => {
    try {
      return sessionStorage.getItem(DISMISS_KEY) === "1";
    } catch {
      return false;
    }
  });

  useEffect(() => {
    if (!portrait) return;
    // После возврата в портрет снова показываем, если не жали «всё равно».
  }, [portrait]);

  if (!coarse || !portrait || dismissed) return null;

  return (
    <div className="landscape-hint" role="dialog" aria-modal="true">
      <div className="landscape-hint__card">
        <div className="landscape-hint__icon" aria-hidden>
          <span className="landscape-hint__phone" />
        </div>
        <h2 className="landscape-hint__title font-display">
          {t.common.landscapeTitle}
        </h2>
        <p className="landscape-hint__body font-ui">{t.common.landscapeBody}</p>
        <button
          type="button"
          className="menu-nav-btn text-sm! landscape-hint__dismiss"
          onClick={() => {
            try {
              sessionStorage.setItem(DISMISS_KEY, "1");
            } catch {
              /* ignore */
            }
            setDismissed(true);
          }}
        >
          {t.common.landscapeAnyway}
        </button>
      </div>
    </div>
  );
}
