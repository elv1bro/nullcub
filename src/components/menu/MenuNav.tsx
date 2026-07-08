import { playMenuSound } from "@/audio";
import { useTranslation } from "@/settings/SettingsContext";

interface Props {
  onPlay: () => void;
  onCustomize: () => void;
  onAchievements: () => void;
  onOptions: () => void;
  onControls: () => void;
  onWorkshop?: () => void;
  locked?: boolean;
}

export function MenuNav({
  onPlay,
  onCustomize,
  onAchievements,
  onOptions,
  onControls,
  onWorkshop,
  locked = false,
}: Props) {
  const t = useTranslation();

  const secondary = (
    label: string,
    icon: string,
    action: () => void,
    sound: "click" | "panel" = "panel",
  ) => (
    <button
      type="button"
      className="menu-nav-btn"
      disabled={locked}
      onClick={() => {
        playMenuSound(sound);
        action();
      }}
      onMouseEnter={() => playMenuSound("hover")}
    >
      <span className="menu-nav-btn__icon" aria-hidden>
        {icon}
      </span>
      {label}
    </button>
  );

  return (
    <nav aria-label="Main menu">
      <div className="menu-btn-pop mb-3">
        <button
          type="button"
          className="menu-nav-btn menu-nav-btn--primary"
          disabled={locked}
          onClick={() => {
            playMenuSound("play");
            onPlay();
          }}
          onMouseEnter={() => playMenuSound("hover")}
        >
          {t.menu.play}
        </button>
      </div>
      <ul className="menu-nav-secondary list-none p-0 m-0">
        <li className="menu-btn-pop">{secondary(t.menu.customize, "◎", onCustomize)}</li>
        <li className="menu-btn-pop">{secondary(t.menu.achievements, "🏅", onAchievements)}</li>
        <li className="menu-btn-pop">{secondary(t.menu.options, "⚙", onOptions)}</li>
        <li className="menu-btn-pop">{secondary(t.menu.controls, "⌨", onControls)}</li>
        {onWorkshop && (
          <li className="menu-btn-pop">
            {secondary(t.menu.workshop, "⚗", onWorkshop)}
          </li>
        )}
      </ul>
    </nav>
  );
}
