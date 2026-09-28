import { playMenuSound } from "@/audio";
import { isDebugMode } from "@/lib/debugMode";
import {
  isLabUnlocked,
  LAB_UNLOCK_CLICKS,
  unlockLab,
} from "@/lib/labMode";
import { useSettings } from "@/settings/SettingsContext";
import { useRef, useState } from "react";

const VERSION = "0.1.0";

interface Props {
  onLabUnlocked?: () => void;
}

export function MenuFooter({ onLabUnlocked }: Props) {
  const { settings, t } = useSettings();
  const lang = settings.language === "ru" ? t.options.langRu : t.options.langEn;
  const clicksRef = useRef(0);
  const [toast, setToast] = useState(false);

  const onVersionClick = () => {
    if (isLabUnlocked()) return;
    clicksRef.current += 1;
    if (clicksRef.current < LAB_UNLOCK_CLICKS) return;
    unlockLab();
    playMenuSound("panel");
    setToast(true);
    onLabUnlocked?.();
    window.setTimeout(() => setToast(false), 2200);
  };

  return (
    <footer className="menu-footer font-ui shrink-0">
      <button
        type="button"
        className="menu-footer__pill menu-footer__pill--tap"
        onClick={onVersionClick}
        title={
          isLabUnlocked()
            ? undefined
            : `${LAB_UNLOCK_CLICKS - clicksRef.current}`
        }
      >
        {t.game.title} {t.game.titleAccent} v{VERSION}
      </button>
      <span className="menu-footer__pill">{lang}</span>
      {(isDebugMode() || isLabUnlocked()) && (
        <span className="menu-footer__pill menu-footer__pill--lab">lab</span>
      )}
      {toast && (
        <span className="menu-footer__pill menu-footer__pill--lab">
          {t.lab.unlockToast}
        </span>
      )}
    </footer>
  );
}
