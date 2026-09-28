import { useAuth } from "@/cloud/AuthContext";
import { playMenuSound } from "@/audio";
import { useViewportFlags } from "@/hooks/useViewportFlags";
import { useTranslation } from "@/settings/SettingsContext";

interface Props {
  onPlay: () => void;
  onCustomize: () => void;
  onAchievements: () => void;
  onAccount: () => void;
  onOptions: () => void;
  onControls: () => void;
  onCredits: () => void;
  onLab?: () => void;
  onWorkshop?: () => void;
  locked?: boolean;
}

export function MenuNav({
  onPlay,
  onCustomize,
  onAchievements,
  onAccount,
  onOptions,
  onControls,
  onCredits,
  onLab,
  onWorkshop,
  locked = false,
}: Props) {
  const t = useTranslation();
  const { coarse } = useViewportFlags();
  const { user, configured } = useAuth();
  // На телефоне только виртуальный стик — переназначение клавиш бессмысленно.
  const accountLabel =
    configured && !user ? t.menu.signIn : t.menu.account;

  const secondary = (
    label: string,
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
        {configured && (
          <li className="menu-btn-pop">{secondary(accountLabel, onAccount)}</li>
        )}
        <li className="menu-btn-pop">{secondary(t.menu.customize, onCustomize)}</li>
        <li className="menu-btn-pop">
          {secondary(t.menu.achievements, onAchievements)}
        </li>
        {onWorkshop && (
          <li className="menu-btn-pop">{secondary(t.menu.workshop, onWorkshop)}</li>
        )}
        <li className="menu-btn-pop">{secondary(t.menu.options, onOptions)}</li>
        {!coarse && (
          <li className="menu-btn-pop">{secondary(t.menu.controls, onControls)}</li>
        )}
        <li className="menu-btn-pop">{secondary(t.menu.credits, onCredits)}</li>
        {onLab && (
          <li className="menu-btn-pop">
            {secondary(t.menu.lab, onLab, "click")}
          </li>
        )}
      </ul>
    </nav>
  );
}
