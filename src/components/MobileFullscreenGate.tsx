import { useFullscreen } from "@/hooks/useFullscreen";
import { useViewportFlags } from "@/hooks/useViewportFlags";
import { useSettings } from "@/settings/SettingsContext";

function shouldSkipGate(): boolean {
  if (typeof window === "undefined") return true;
  if (new URLSearchParams(window.location.search).has("e2e")) return true;
  if (navigator.webdriver) return true;
  return false;
}

/**
 * На телефоне после заставки — обязательный тап «На весь экран».
 * Пока не в fullscreen (или в портрете без API) — меню перекрыто.
 */
export function MobileFullscreenGate() {
  const { t } = useSettings();
  const { coarse, portrait } = useViewportFlags();
  const { supported, active, enter } = useFullscreen();

  if (shouldSkipGate() || !coarse) return null;

  // Fullscreen есть, но ещё не включён — главная блокировка.
  const needFullscreen = supported && !active;
  // Нет FS API (часто iPhone) или уже FS, но портрет — требуем альбом.
  const needLandscape = (!supported || active) && portrait;

  if (!needFullscreen && !needLandscape) return null;

  return (
    <div className="mobile-fs-gate" role="dialog" aria-modal="true">
      <div className="mobile-fs-gate__card">
        <div className="mobile-fs-gate__icon" aria-hidden>
          <span className="mobile-fs-gate__phone" />
        </div>
        {needFullscreen ? (
          <>
            <h2 className="mobile-fs-gate__title font-display">
              {t.common.fullscreenGateTitle}
            </h2>
            <p className="mobile-fs-gate__body font-ui">
              {t.common.fullscreenGateBody}
            </p>
            <button
              type="button"
              className="menu-nav-btn menu-nav-btn--primary mobile-fs-gate__btn"
              onClick={enter}
            >
              {t.common.fullscreenEnter}
            </button>
          </>
        ) : (
          <>
            <h2 className="mobile-fs-gate__title font-display">
              {t.common.landscapeTitle}
            </h2>
            <p className="mobile-fs-gate__body font-ui">
              {t.common.landscapeBody}
            </p>
          </>
        )}
      </div>
    </div>
  );
}
