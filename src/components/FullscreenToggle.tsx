import { useFullscreen } from "@/hooks/useFullscreen";
import { useViewportFlags } from "@/hooks/useViewportFlags";
import { useSettings } from "@/settings/SettingsContext";

/**
 * Кнопка полноэкрана для телефона (если API доступен).
 * На iPhone Safari обычно скрыта — там fullscreen почти не дают.
 */
export function FullscreenToggle({
  visible = true,
}: {
  visible?: boolean;
}) {
  const { t } = useSettings();
  const { coarse } = useViewportFlags();
  const { supported, active, toggle } = useFullscreen();

  if (!visible || !coarse || !supported) return null;

  return (
    <button
      type="button"
      className="battle-fs-toggle"
      onClick={toggle}
      aria-pressed={active}
      aria-label={active ? t.common.fullscreenExit : t.common.fullscreenEnter}
      title={active ? t.common.fullscreenExit : t.common.fullscreenEnter}
    >
      {active ? <ExitFsIcon /> : <EnterFsIcon />}
    </button>
  );
}

function EnterFsIcon() {
  return (
    <svg viewBox="0 0 24 24" className="battle-fs-toggle__icon" aria-hidden>
      <path
        d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ExitFsIcon() {
  return (
    <svg viewBox="0 0 24 24" className="battle-fs-toggle__icon" aria-hidden>
      <path
        d="M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
