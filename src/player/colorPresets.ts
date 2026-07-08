import type { Language } from "@/i18n";
import type { FighterColors } from "@/lib/fighterColors";

export interface ColorPreset extends FighterColors {
  id: string;
  label: Record<Language, string>;
}

export const COLOR_PRESETS: ColorPreset[] = [
  { id: "sky", label: { en: "Sky", ru: "Небо" }, main: "#38bdf8", secondary: "#0284c7" },
  { id: "crimson", label: { en: "Crimson", ru: "Багровый" }, main: "#f87171", secondary: "#b91c1c" },
  { id: "jade", label: { en: "Jade", ru: "Нефрит" }, main: "#4ade80", secondary: "#15803d" },
  { id: "violet", label: { en: "Violet", ru: "Фиолет" }, main: "#c084fc", secondary: "#7e22ce" },
  { id: "gold", label: { en: "Gold", ru: "Золото" }, main: "#fbbf24", secondary: "#b45309" },
  { id: "rose", label: { en: "Rose", ru: "Роза" }, main: "#fb7185", secondary: "#be123c" },
  { id: "mint", label: { en: "Mint", ru: "Мята" }, main: "#2dd4bf", secondary: "#0f766e" },
  { id: "orange", label: { en: "Blaze", ru: "Пламя" }, main: "#fb923c", secondary: "#c2410c" },
  { id: "lime", label: { en: "Lime", ru: "Лайм" }, main: "#a3e635", secondary: "#4d7c0f" },
  { id: "indigo", label: { en: "Indigo", ru: "Индиго" }, main: "#818cf8", secondary: "#4338ca" },
  { id: "pink", label: { en: "Bubblegum", ru: "Жвачка" }, main: "#f472b6", secondary: "#be185d" },
  { id: "steel", label: { en: "Steel", ru: "Сталь" }, main: "#94a3b8", secondary: "#475569" },
  { id: "copper", label: { en: "Copper", ru: "Медь" }, main: "#fdba74", secondary: "#9a3412" },
  { id: "ice", label: { en: "Ice", ru: "Лёд" }, main: "#e0f2fe", secondary: "#0369a1" },
  { id: "toxic", label: { en: "Toxic", ru: "Токсин" }, main: "#bef264", secondary: "#3f6212" },
  { id: "royal", label: { en: "Royal", ru: "Король" }, main: "#a78bfa", secondary: "#5b21b6" },
  { id: "sunset", label: { en: "Sunset", ru: "Закат" }, main: "#f97316", secondary: "#7c2d12" },
  { id: "ocean", label: { en: "Ocean", ru: "Океан" }, main: "#22d3ee", secondary: "#155e75" },
  { id: "cherry", label: { en: "Cherry", ru: "Вишня" }, main: "#ef4444", secondary: "#7f1d1d" },
  { id: "ghost", label: { en: "Ghost", ru: "Призрак" }, main: "#e2e8f0", secondary: "#64748b" },
  { id: "neon", label: { en: "Neon", ru: "Неон" }, main: "#22c55e", secondary: "#14532d" },
  { id: "plasma", label: { en: "Plasma", ru: "Плазма" }, main: "#d946ef", secondary: "#86198f" },
  { id: "sand", label: { en: "Sand", ru: "Песок" }, main: "#fcd34d", secondary: "#92400e" },
  { id: "midnight", label: { en: "Midnight", ru: "Полночь" }, main: "#6366f1", secondary: "#1e1b4b" },
];

export function presetColors(preset: ColorPreset): FighterColors {
  return { main: preset.main, secondary: preset.secondary };
}

export function isPresetActive(
  preset: ColorPreset,
  colors: FighterColors,
): boolean {
  return preset.main === colors.main && preset.secondary === colors.secondary;
}

export function findMatchingPreset(colors: FighterColors): ColorPreset | null {
  return COLOR_PRESETS.find((p) => isPresetActive(p, colors)) ?? null;
}
