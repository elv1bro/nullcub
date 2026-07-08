import { isDebugMode } from "@/lib/debugMode";
import { useSettings } from "@/settings/SettingsContext";

const VERSION = "0.1.0";

export function MenuFooter() {
  const { settings, t } = useSettings();
  const lang = settings.language === "ru" ? t.options.langRu : t.options.langEn;

  return (
    <footer className="menu-footer font-ui shrink-0">
      <span className="menu-footer__pill">Ragdoll Riot v{VERSION}</span>
      <span className="menu-footer__pill">{lang}</span>
      {isDebugMode() && (
        <span className="menu-footer__pill text-yellow-300/80">debug</span>
      )}
    </footer>
  );
}
