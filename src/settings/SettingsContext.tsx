import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";
import { getLocale, type Language, type LocaleStrings } from "@/i18n";

export type { Language };
import { migrateBinding } from "@/input/keyBindings";
import {
  DEFAULT_MUSIC_VOLUME,
  DEFAULT_SFX_VOLUME,
  setMusicEnabled as applyMusicEnabled,
  setMusicVolume as applyMusicVolume,
  setSfxVolume as applySfxVolume,
  setSoundEffectsEnabled,
} from "@/audio";
import { isTestEnv } from "@/audio/isTestEnv";

export interface ControlBindings {
  up: string;
  down: string;
  left: string;
  right: string;
}

export interface AbilityBindings {
  dash: string;
  flip: string;
  freeze: string;
  grabL: string;
  grabR: string;
  /** Зарезервировано под 4-ю способность */
  slot4: string;
  reset: string;
}

export interface GameSettings {
  language: Language;
  controls: ControlBindings;
  /** Управление вторым игроком на одном ПК (стрелки по умолчанию). */
  controlsP2: ControlBindings;
  abilities: AbilityBindings;
  /** Хват второго локального игрока (U / I по умолчанию). */
  abilitiesP2: AbilityBindings;
  showBanter: boolean;
  /** Мат и грубый юмор в репликах при ударах */
  matureBanter: boolean;
  screenEffects: boolean;
  soundEffects: boolean;
  /** Громкость звуковых эффектов 0..1 */
  sfxVolume: number;
  /** Музыка включена (меню + бой) */
  musicEnabled: boolean;
  /** Громкость музыки 0..1, дефолт 0.3 */
  musicVolume: number;
}

const STORAGE_KEY = "ragdoll-riot-settings";

export const DEFAULT_CONTROLS: ControlBindings = {
  up: "KeyW",
  down: "KeyS",
  left: "KeyA",
  right: "KeyD",
};

export const DEFAULT_ABILITIES: AbilityBindings = {
  dash: "Digit6",
  flip: "Digit7",
  freeze: "Digit8",
  grabL: "KeyQ",
  grabR: "KeyE",
  slot4: "Digit9",
  reset: "Digit0",
};

export const DEFAULT_CONTROLS_P2: ControlBindings = {
  up: "ArrowUp",
  down: "ArrowDown",
  left: "ArrowLeft",
  right: "ArrowRight",
};

export const DEFAULT_ABILITIES_P2: AbilityBindings = {
  dash: "Numpad6",
  flip: "Numpad7",
  freeze: "Numpad8",
  grabL: "KeyU",
  grabR: "KeyI",
  slot4: "Numpad9",
  reset: "Numpad0",
};

export const DEFAULT_SETTINGS: GameSettings = {
  language: "ru",
  controls: DEFAULT_CONTROLS,
  controlsP2: DEFAULT_CONTROLS_P2,
  abilities: DEFAULT_ABILITIES,
  abilitiesP2: DEFAULT_ABILITIES_P2,
  showBanter: true,
  matureBanter: false,
  screenEffects: true,
  soundEffects: !isTestEnv(),
  sfxVolume: isTestEnv() ? 0 : DEFAULT_SFX_VOLUME,
  musicEnabled: !isTestEnv(),
  musicVolume: isTestEnv() ? 0 : DEFAULT_MUSIC_VOLUME,
};

function migrateControls(raw?: Partial<ControlBindings>): ControlBindings {
  return {
    up: migrateBinding(raw?.up ?? DEFAULT_CONTROLS.up),
    down: migrateBinding(raw?.down ?? DEFAULT_CONTROLS.down),
    left: migrateBinding(raw?.left ?? DEFAULT_CONTROLS.left),
    right: migrateBinding(raw?.right ?? DEFAULT_CONTROLS.right),
  };
}

function migrateAbilities(raw?: Partial<AbilityBindings>): AbilityBindings {
  return {
    dash: migrateBinding(raw?.dash ?? DEFAULT_ABILITIES.dash),
    flip: migrateBinding(raw?.flip ?? DEFAULT_ABILITIES.flip),
    freeze: migrateBinding(raw?.freeze ?? DEFAULT_ABILITIES.freeze),
    grabL: migrateBinding(raw?.grabL ?? DEFAULT_ABILITIES.grabL),
    grabR: migrateBinding(raw?.grabR ?? DEFAULT_ABILITIES.grabR),
    slot4: migrateBinding(raw?.slot4 ?? DEFAULT_ABILITIES.slot4),
    reset: migrateBinding(raw?.reset ?? DEFAULT_ABILITIES.reset),
  };
}

function loadSettings(): GameSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_SETTINGS;
    const parsed = JSON.parse(raw) as Partial<GameSettings>;
    return {
      language: parsed.language === "en" ? "en" : "ru",
      controls: migrateControls(parsed.controls),
      controlsP2: migrateControls(parsed.controlsP2 ?? DEFAULT_CONTROLS_P2),
      abilities: migrateAbilities(parsed.abilities),
      abilitiesP2: migrateAbilities(parsed.abilitiesP2 ?? DEFAULT_ABILITIES_P2),
      showBanter: parsed.showBanter ?? DEFAULT_SETTINGS.showBanter,
      matureBanter: parsed.matureBanter ?? DEFAULT_SETTINGS.matureBanter,
      screenEffects: parsed.screenEffects ?? DEFAULT_SETTINGS.screenEffects,
      soundEffects: parsed.soundEffects ?? DEFAULT_SETTINGS.soundEffects,
      sfxVolume:
        typeof parsed.sfxVolume === "number"
          ? Math.max(0, Math.min(1, parsed.sfxVolume))
          : DEFAULT_SETTINGS.sfxVolume,
      musicEnabled: parsed.musicEnabled ?? DEFAULT_SETTINGS.musicEnabled,
      musicVolume:
        typeof parsed.musicVolume === "number"
          ? Math.max(0, Math.min(1, parsed.musicVolume))
          : DEFAULT_SETTINGS.musicVolume,
    };
  } catch {
    return DEFAULT_SETTINGS;
  }
}

function saveSettings(settings: GameSettings): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
}

type ControlDirection = keyof ControlBindings;
type AbilitySlot = keyof AbilityBindings;

interface SettingsContextValue {
  settings: GameSettings;
  t: LocaleStrings;
  setLanguage: (language: Language) => void;
  setControl: (direction: ControlDirection, code: string) => void;
  setControlP2: (direction: ControlDirection, code: string) => void;
  setAbility: (slot: AbilitySlot, code: string) => void;
  setAbilityP2: (slot: AbilitySlot, code: string) => void;
  resetControls: () => void;
  setShowBanter: (value: boolean) => void;
  setMatureBanter: (value: boolean) => void;
  setScreenEffects: (value: boolean) => void;
  setSoundEffects: (value: boolean) => void;
  setSfxVolume: (value: number) => void;
  setMusicEnabled: (value: boolean) => void;
  setMusicVolume: (value: number) => void;
}

const SettingsContext = createContext<SettingsContextValue | null>(null);

export function SettingsProvider({ children }: PropsWithChildren) {
  const [settings, setSettings] = useState<GameSettings>(loadSettings);

  const persist = useCallback(
    (patch: (prev: GameSettings) => GameSettings) => {
      setSettings((prev) => {
        const next = patch(prev);
        saveSettings(next);
        return next;
      });
    },
    [],
  );

  useEffect(() => {
    document.documentElement.lang = settings.language;
  }, [settings.language]);

  useEffect(() => {
    setSoundEffectsEnabled(settings.soundEffects);
  }, [settings.soundEffects]);

  useEffect(() => {
    applySfxVolume(settings.sfxVolume);
  }, [settings.sfxVolume]);

  useEffect(() => {
    applyMusicVolume(settings.musicVolume);
  }, [settings.musicVolume]);

  useEffect(() => {
    applyMusicEnabled(settings.musicEnabled);
  }, [settings.musicEnabled]);

  const value = useMemo<SettingsContextValue>(
    () => ({
      settings,
      t: getLocale(settings.language),
      setLanguage: (language) => persist((prev) => ({ ...prev, language })),
      setControl: (direction, code) =>
        persist((prev) => ({
          ...prev,
          controls: {
            ...prev.controls,
            [direction]: migrateBinding(code),
          },
        })),
      setControlP2: (direction, code) =>
        persist((prev) => ({
          ...prev,
          controlsP2: {
            ...prev.controlsP2,
            [direction]: migrateBinding(code),
          },
        })),
      setAbility: (slot, code) =>
        persist((prev) => ({
          ...prev,
          abilities: {
            ...prev.abilities,
            [slot]: migrateBinding(code),
          },
        })),
      setAbilityP2: (slot, code) =>
        persist((prev) => ({
          ...prev,
          abilitiesP2: {
            ...prev.abilitiesP2,
            [slot]: migrateBinding(code),
          },
        })),
      resetControls: () =>
        persist((prev) => ({
          ...prev,
          controls: { ...DEFAULT_CONTROLS },
          controlsP2: { ...DEFAULT_CONTROLS_P2 },
          abilities: { ...DEFAULT_ABILITIES },
          abilitiesP2: { ...DEFAULT_ABILITIES_P2 },
        })),
      setShowBanter: (showBanter) =>
        persist((prev) => ({ ...prev, showBanter })),
      setMatureBanter: (matureBanter) =>
        persist((prev) => ({ ...prev, matureBanter })),
      setScreenEffects: (screenEffects) =>
        persist((prev) => ({ ...prev, screenEffects })),
      setSoundEffects: (soundEffects) =>
        persist((prev) => ({ ...prev, soundEffects })),
      setSfxVolume: (value) =>
        persist((prev) => ({
          ...prev,
          sfxVolume: Math.max(0, Math.min(1, value)),
          soundEffects: value > 0 ? true : prev.soundEffects,
        })),
      setMusicEnabled: (musicEnabled) =>
        persist((prev) => ({ ...prev, musicEnabled })),
      setMusicVolume: (value) =>
        persist((prev) => ({
          ...prev,
          musicVolume: Math.max(0, Math.min(1, value)),
          // Регулировка громкости автоматически включает музыку обратно
          musicEnabled: value > 0 ? true : prev.musicEnabled,
        })),
    }),
    [persist, settings],
  );

  return (
    <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>
  );
}

export function useSettings(): SettingsContextValue {
  const ctx = useContext(SettingsContext);
  if (!ctx) {
    throw new Error("useSettings must be used within SettingsProvider");
  }
  return ctx;
}

/** Shortcut for strings only */
export function useTranslation(): LocaleStrings {
  return useSettings().t;
}
