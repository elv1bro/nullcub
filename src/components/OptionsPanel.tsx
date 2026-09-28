import { AccountPanel } from "@/components/AccountPanel";
import { Button } from "@/components/Button";
import { useSettings, type Language } from "@/settings/SettingsContext";

interface Props {
  embedded?: boolean;
  onClose?: () => void;
}

export function OptionsPanel({ embedded, onClose }: Props) {
  const {
    t,
    settings,
    setLanguage,
    setShowBanter,
    setMatureBanter,
    setScreenEffects,
    setSoundEffects,
    setSfxVolume,
    setMusicEnabled,
    setMusicVolume,
  } = useSettings();

  const musicPct = Math.round(settings.musicVolume * 100);
  const sfxPct = Math.round(settings.sfxVolume * 100);

  const inner = (
    <>
      <AccountPanel />

      <label className="menu-field">
        <span className="menu-label">{t.options.language}</span>
        <select
          value={settings.language}
          onChange={(e) => setLanguage(e.target.value as Language)}
          className="menu-select"
        >
          <option value="ru">{t.options.langRu}</option>
          <option value="en">{t.options.langEn}</option>
        </select>
      </label>

      <label className="flex items-center gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={settings.showBanter}
          onChange={(e) => setShowBanter(e.target.checked)}
          className="w-4 h-4"
        />
        <span className="font-ui text-sm text-gray-300">{t.options.showBanter}</span>
      </label>

      {settings.showBanter && (
        <label className="flex items-start gap-2 cursor-pointer pl-6">
          <input
            type="checkbox"
            checked={settings.matureBanter}
            onChange={(e) => setMatureBanter(e.target.checked)}
            className="w-4 h-4 mt-0.5"
          />
          <span className="font-ui text-sm text-gray-300">
            {t.options.matureBanter}
            <span className="block text-xs text-gray-500 mt-0.5">
              {t.options.matureBanterHint}
            </span>
          </span>
        </label>
      )}

      <label className="flex items-center gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={settings.screenEffects}
          onChange={(e) => setScreenEffects(e.target.checked)}
          className="w-4 h-4"
        />
        <span className="font-ui text-sm text-gray-300">{t.options.screenEffects}</span>
      </label>

      <label className="flex items-center gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={settings.soundEffects}
          onChange={(e) => setSoundEffects(e.target.checked)}
          className="w-4 h-4"
        />
        <span className="font-ui text-sm text-gray-300">{t.options.soundEffects}</span>
      </label>

      {settings.soundEffects && (
        <label className="menu-field pl-6">
          <span className="menu-label">
            {t.options.sfxVolume} — {sfxPct}%
          </span>
          <input
            type="range"
            min={0}
            max={100}
            step={5}
            value={sfxPct}
            onChange={(e) => setSfxVolume(Number(e.target.value) / 100)}
            className="w-full accent-cyan-400"
          />
        </label>
      )}

      <label className="flex items-center gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={settings.musicEnabled}
          onChange={(e) => setMusicEnabled(e.target.checked)}
          className="w-4 h-4"
        />
        <span className="font-ui text-sm text-gray-300">{t.options.music}</span>
      </label>

      {settings.musicEnabled && (
        <label className="menu-field pl-6">
          <span className="menu-label">
            {t.options.musicVolume} — {musicPct}%
          </span>
          <input
            type="range"
            min={0}
            max={100}
            step={5}
            value={musicPct}
            onChange={(e) => setMusicVolume(Number(e.target.value) / 100)}
            className="w-full accent-cyan-400"
          />
        </label>
      )}

      {!embedded && onClose && (
        <Button type="button" className="text-sm py-1 w-full" onClick={onClose}>
          {t.options.close}
        </Button>
      )}
    </>
  );

  if (embedded) return <div className="menu-stack">{inner}</div>;

  return (
    <div className="menu-panel-surface menu-panel-pad menu-stack w-full max-w-xs">
      <h3 className="menu-panel-title">{t.options.title}</h3>
      {inner}
    </div>
  );
}
