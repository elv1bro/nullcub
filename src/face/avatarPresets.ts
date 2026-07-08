import type { Language } from "@/i18n";
import { generateAvatarRoster } from "./avatarRoster";

/** Вид персонажа — определяет, каким painter'ом рисуется лицо. */
export type AvatarKind =
  | "human"
  | "cat"
  | "fox"
  | "panda"
  | "frog"
  | "bear"
  | "tiger"
  | "owl"
  | "bunny"
  | "shiba"
  | "penguin"
  | "axolotl"
  | "unicorn"
  | "robot"
  | "alien"
  | "zombie"
  | "skull"
  | "oni"
  | "pumpkin"
  | "ghost"
  | "ninja"
  | "slime";

/** Дефолтное выражение лица: превью и «спокойное» состояние в бою. */
export type AvatarMood = "neutral" | "smile" | "angry" | "scared" | "surprised";

export type HumanHairStyle =
  | "mohawk"
  | "afro"
  | "buns"
  | "spiky"
  | "long"
  | "braids"
  | "granny"
  | "bald";

export interface HumanTraits {
  hair: HumanHairStyle;
  beard?: boolean;
  glasses?: boolean;
  freckles?: boolean;
  earrings?: boolean;
}

export interface AvatarFacePreset {
  id: string;
  label: Record<Language, string>;
  kind: AvatarKind;
  mood: AvatarMood;
  /** Основной цвет: кожа / шерсть / корпус. */
  primary: string;
  /** Тень основного цвета. */
  shade: string;
  /** Акцент: волосы / грива / уши / светящиеся детали. */
  accent: string;
  /** Второй акцент / подсветка акцента. */
  accent2: string;
  /** Цвет глаз (радужка или свечение). */
  eyes: string;
  human?: HumanTraits;
}

const P = (
  id: string,
  en: string,
  ru: string,
  kind: AvatarKind,
  mood: AvatarMood,
  primary: string,
  shade: string,
  accent: string,
  accent2: string,
  eyes: string,
  human?: HumanTraits,
): AvatarFacePreset => ({
  id,
  label: { en, ru },
  kind,
  mood,
  primary,
  shade,
  accent,
  accent2,
  eyes,
  ...(human ? { human } : {}),
});

/** Кураторские «именные» лица — показываются первыми в карусели. */
const CURATED_PRESETS: AvatarFacePreset[] = [
  // ── звери ──
  P("cat", "Cat", "Кот", "cat", "neutral", "#f0953c", "#c2661a", "#fff4e6", "#8a4a12", "#86c93c"),
  P("fox", "Fox", "Лиса", "fox", "smile", "#f07f2e", "#bd5416", "#fff7ef", "#3a2417", "#d99114"),
  P("panda", "Panda", "Панда", "panda", "smile", "#f7f3ee", "#d3c8bc", "#2b2724", "#454038", "#4a3324"),
  P("shiba", "Shiba", "Сиба", "shiba", "smile", "#f2b25c", "#cd8730", "#fdf3e4", "#6b4a24", "#33241a"),
  P("bunny", "Bunny", "Зая", "bunny", "scared", "#f0ebe7", "#c9bcb2", "#ffb7c9", "#a89a92", "#3a2e28"),
  P("bear", "Bear", "Мишка", "bear", "neutral", "#9c6b3f", "#6f4520", "#d9a86e", "#4c2e12", "#2f1d0e"),
  P("tiger", "Tiger", "Тигр", "tiger", "angry", "#f59e2d", "#c96f12", "#fdf6ec", "#221a12", "#9fd53a"),
  P("owl", "Owl", "Сова", "owl", "surprised", "#a97c50", "#7a532c", "#ead7ba", "#5c3f22", "#ffc21c"),
  P("frog", "Frog", "Лягух", "frog", "neutral", "#6fc93c", "#459122", "#b4ec7c", "#2f6b16", "#2a1c0c"),
  P("penguin", "Penguin", "Пингвин", "penguin", "neutral", "#33404f", "#1c2530", "#f2f5f7", "#ffb02e", "#1d232b"),
  P("axolotl", "Axolotl", "Аксолотль", "axolotl", "smile", "#ffb3c4", "#ec8aa2", "#ff5f8f", "#ff90b3", "#4a3440"),
  P("unicorn", "Unicorn", "Единорог", "unicorn", "smile", "#fdf4fa", "#dfc6de", "#ffd23e", "#ff8fc0", "#7a5fc0"),
  // ── люди ──
  P("kai", "Kai", "Кай", "human", "angry", "#f2c9a4", "#cf9868", "#19d3c5", "#7ff0e6", "#2f4f5f", {
    hair: "mohawk",
  }),
  P("zara", "Zara", "Зара", "human", "smile", "#7a4a26", "#523016", "#181209", "#3a2c1e", "#3d2314", {
    hair: "afro",
    earrings: true,
  }),
  P("bjorn", "Björn", "Бьёрн", "human", "angry", "#f5d3b3", "#d3a071", "#c0561e", "#e87f35", "#3f6f8f", {
    hair: "braids",
    beard: true,
    freckles: true,
  }),
  P("yuki", "Yuki", "Юки", "human", "smile", "#ffe3d2", "#ecbda4", "#ff79b0", "#ffa9cc", "#5a4a8f", {
    hair: "buns",
  }),
  P("spike", "Spike", "Спайк", "human", "surprised", "#edbd8e", "#c98c54", "#ffcf24", "#ffe97a", "#4a6741", {
    hair: "spiky",
  }),
  P("luna", "Luna", "Луна", "human", "neutral", "#f7e3d8", "#d9b5a3", "#6f4fd8", "#9d7bf0", "#7a56c9", {
    hair: "long",
  }),
  P("rosa", "Rosa", "Роза", "human", "smile", "#f0cdb4", "#cc9c7c", "#d8d4d0", "#f2efec", "#52708a", {
    hair: "granny",
    glasses: true,
  }),
  P("nova", "Nova", "Нова", "human", "smile", "#8d5a30", "#613a19", "#f0c14b", "#ffe08a", "#241a10", {
    hair: "bald",
    earrings: true,
  }),
  // ── монстры и прочие ──
  P("robot", "Robot", "Робот", "robot", "neutral", "#9fb2c8", "#5f7188", "#3ad6ff", "#ff5470", "#3ad6ff"),
  P("alien", "Alien", "Пришелец", "alien", "neutral", "#8fd648", "#569c26", "#141018", "#c7f08a", "#141018"),
  P("zombie", "Zombie", "Зомби", "zombie", "neutral", "#a9c46c", "#6f9144", "#4a5d33", "#d7e6ac", "#e8e4d8"),
  P("skull", "Skull", "Череп", "skull", "smile", "#f2ede2", "#c3b9a4", "#221d18", "#7de24a", "#7de24a"),
  P("oni", "Oni", "Они", "oni", "angry", "#d8342e", "#97181c", "#f7c948", "#241612", "#ffd84a"),
  P("pumpkin", "Pumpkin", "Тыква", "pumpkin", "smile", "#f5871f", "#bf540c", "#6a9a2a", "#ffd94a", "#ffd94a"),
  P("ghost", "Ghost", "Призрак", "ghost", "surprised", "#eef3fb", "#b3c3de", "#8fa7d0", "#ffffff", "#2c3350"),
  P("ninja", "Ninja", "Ниндзя", "ninja", "angry", "#333a4c", "#1d222f", "#e8b98a", "#e23c3c", "#2a2018"),
  P("slime", "Slime", "Слайм", "slime", "smile", "#4fd8a0", "#23a26e", "#baf5dd", "#ffffff", "#1e4a3a"),
];

/**
 * Полный ростер: кураторские + процедурные вариации (детерминированные,
 * одинаковые на всех клиентах — id безопасно гонять по сети и хранить в профиле).
 */
export const AVATAR_FACE_PRESETS: AvatarFacePreset[] = [
  ...CURATED_PRESETS,
  ...generateAvatarRoster(),
];

const PRESET_BY_ID = new Map(AVATAR_FACE_PRESETS.map((p) => [p.id, p]));

export const DEFAULT_AVATAR_FACE_ID = AVATAR_FACE_PRESETS[0]!.id;

export function getAvatarFacePreset(id: string | undefined): AvatarFacePreset {
  return PRESET_BY_ID.get(id ?? "") ?? AVATAR_FACE_PRESETS[0]!;
}

export function isValidAvatarFaceId(id: string): boolean {
  return PRESET_BY_ID.has(id);
}

/**
 * Детерминированный выбор лица врага по сиду (id уровня кампании, имя босса…):
 * один сид — всегда одно лицо.
 */
export function avatarFaceIdForSeed(seed: string): string {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i += 1) {
    h = Math.imul(h ^ seed.charCodeAt(i), 16777619);
  }
  return AVATAR_FACE_PRESETS[(h >>> 0) % AVATAR_FACE_PRESETS.length]!.id;
}
