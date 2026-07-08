import type {
  AvatarFacePreset,
  AvatarKind,
  AvatarMood,
  HumanHairStyle,
  HumanTraits,
} from "./avatarPresets";
import { darken, lighten } from "./color";

/**
 * Процедурная часть ростера лиц: детерминированно (фиксированный сид)
 * разворачивает painter-виды в сотни вариаций палитр, настроений и причёсок.
 * Один и тот же список получается на любом клиенте — id можно слать по сети.
 */

const MOODS: readonly AvatarMood[] = [
  "neutral",
  "smile",
  "angry",
  "scared",
  "surprised",
];

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffled<T>(items: readonly T[], rnd: () => number): T[] {
  const arr = [...items];
  for (let i = arr.length - 1; i > 0; i -= 1) {
    const j = Math.floor(rnd() * (i + 1));
    const tmp = arr[i]!;
    arr[i] = arr[j]!;
    arr[j] = tmp;
  }
  return arr;
}

interface Palette {
  primary: string;
  shade?: string;
  accent: string;
  accent2: string;
  eyes: string;
}

type NonHumanKind = Exclude<AvatarKind, "human">;

const KIND_PALETTES: Record<NonHumanKind, readonly Palette[]> = {
  cat: [
    { primary: "#f0953c", accent: "#fff4e6", accent2: "#8a4a12", eyes: "#86c93c" },
    { primary: "#43434e", accent: "#7d7d8a", accent2: "#2b2b34", eyes: "#ffd23e" },
    { primary: "#f2efe9", accent: "#ffffff", accent2: "#d8d0c2", eyes: "#6db3f2" },
    { primary: "#9a9aa6", accent: "#e8e8ee", accent2: "#5c5c68", eyes: "#ffb02e" },
    { primary: "#e8d5bc", accent: "#f9f0e2", accent2: "#a0805a", eyes: "#5fa8e8" },
    { primary: "#8a5f38", accent: "#d9c2a4", accent2: "#4a3018", eyes: "#a8d84a" },
  ],
  fox: [
    { primary: "#f07f2e", accent: "#fff7ef", accent2: "#3a2417", eyes: "#d99114" },
    { primary: "#eef0f4", accent: "#ffffff", accent2: "#b9c2cf", eyes: "#4a90d9" },
    { primary: "#8c8c9a", accent: "#e4e4ec", accent2: "#3c3c46", eyes: "#ffc21c" },
    { primary: "#d9b26a", accent: "#f7ecd4", accent2: "#8a6a34", eyes: "#6a9a3a" },
    { primary: "#c0501e", accent: "#f2d9c4", accent2: "#2e1a10", eyes: "#ffd23e" },
  ],
  panda: [
    { primary: "#f7f3ee", accent: "#2b2724", accent2: "#454038", eyes: "#4a3324" },
    { primary: "#efe6da", accent: "#7a5a3c", accent2: "#96745a", eyes: "#4a3324" },
    { primary: "#e6e2ea", accent: "#3f3a52", accent2: "#57506e", eyes: "#5a4a8f" },
  ],
  frog: [
    { primary: "#6fc93c", accent: "#b4ec7c", accent2: "#2f6b16", eyes: "#2a1c0c" },
    { primary: "#4aa8e8", accent: "#a4d8f7", accent2: "#205a8a", eyes: "#16323f" },
    { primary: "#e85a3a", accent: "#f7c4a4", accent2: "#8a2a16", eyes: "#2a180c" },
    { primary: "#e8c83a", accent: "#f7e9a4", accent2: "#8a7016", eyes: "#3a2c0c" },
    { primary: "#9a6ad8", accent: "#d4baf2", accent2: "#55338a", eyes: "#2c1c3f" },
  ],
  bear: [
    { primary: "#9c6b3f", accent: "#d9a86e", accent2: "#4c2e12", eyes: "#2f1d0e" },
    { primary: "#4a4048", accent: "#8a7a80", accent2: "#241e24", eyes: "#d9a83c" },
    { primary: "#f0ede6", accent: "#fbf9f4", accent2: "#c9c2b2", eyes: "#3a3f52" },
    { primary: "#d9a45a", accent: "#f2d9a8", accent2: "#8a5f24", eyes: "#6b4a1c" },
  ],
  tiger: [
    { primary: "#f59e2d", accent: "#fdf6ec", accent2: "#221a12", eyes: "#9fd53a" },
    { primary: "#f0ede6", accent: "#ffffff", accent2: "#2b2b34", eyes: "#5fa8e8" },
    { primary: "#3c3540", accent: "#6e6474", accent2: "#17131c", eyes: "#ffd23e" },
    { primary: "#e8b84a", accent: "#f9ecc9", accent2: "#8a5a14", eyes: "#4a90d9" },
  ],
  owl: [
    { primary: "#a97c50", accent: "#ead7ba", accent2: "#5c3f22", eyes: "#ffc21c" },
    { primary: "#eff0f2", accent: "#ffffff", accent2: "#b9bfca", eyes: "#e8a41c" },
    { primary: "#8f8f9c", accent: "#d8d8e2", accent2: "#4c4c58", eyes: "#ff8f1c" },
    { primary: "#c08a48", accent: "#f2dcbc", accent2: "#6e4a1e", eyes: "#e8791c" },
  ],
  bunny: [
    { primary: "#f0ebe7", accent: "#ffb7c9", accent2: "#a89a92", eyes: "#3a2e28" },
    { primary: "#b9b4bf", accent: "#f2a8bc", accent2: "#7a7580", eyes: "#33282f" },
    { primary: "#c09a6e", accent: "#f2b8a8", accent2: "#8a6a42", eyes: "#3f2c18" },
    { primary: "#4a4550", accent: "#c9738f", accent2: "#2b2730", eyes: "#d9c23c" },
    { primary: "#f2e2c4", accent: "#ffc9d4", accent2: "#c9b28a", eyes: "#4a3828" },
  ],
  shiba: [
    { primary: "#f2b25c", accent: "#fdf3e4", accent2: "#6b4a24", eyes: "#33241a" },
    { primary: "#f2ddb4", accent: "#fdf6e8", accent2: "#a08a5c", eyes: "#3a2c1a" },
    { primary: "#4c4452", accent: "#d9b48a", accent2: "#2b2530", eyes: "#d9b43c" },
    { primary: "#f4f0ea", accent: "#ffffff", accent2: "#c4bcb0", eyes: "#3a3028" },
  ],
  penguin: [
    { primary: "#33404f", accent: "#f2f5f7", accent2: "#ffb02e", eyes: "#1d232b" },
    { primary: "#23262e", accent: "#fbfbf6", accent2: "#e8632e", eyes: "#16181f" },
    { primary: "#3a5a8a", accent: "#e8f0f7", accent2: "#f2c22e", eyes: "#1a2738" },
  ],
  axolotl: [
    { primary: "#ffb3c4", accent: "#ff5f8f", accent2: "#ff90b3", eyes: "#4a3440" },
    { primary: "#d0b3f2", accent: "#9a5fd8", accent2: "#b48fe8", eyes: "#3a2c50" },
    { primary: "#a4e2e8", accent: "#3aa8bc", accent2: "#7accd8", eyes: "#1e444c" },
    { primary: "#f2d9a4", accent: "#e8a83a", accent2: "#f2c46a", eyes: "#4c3a14" },
    { primary: "#6a6a7c", accent: "#c05a8a", accent2: "#8a8aa0", eyes: "#e2e2ec" },
  ],
  unicorn: [
    { primary: "#fdf4fa", accent: "#ffd23e", accent2: "#ff8fc0", eyes: "#7a5fc0" },
    { primary: "#ffd9ea", accent: "#d9d9e8", accent2: "#ff6aa8", eyes: "#8a4a9a" },
    { primary: "#d9f2e4", accent: "#ffd23e", accent2: "#4ac9a0", eyes: "#2c6a52" },
    { primary: "#4a4a72", accent: "#d9d9e8", accent2: "#8f6af2", eyes: "#ffd23e" },
  ],
  robot: [
    { primary: "#9fb2c8", accent: "#3ad6ff", accent2: "#ff5470", eyes: "#3ad6ff" },
    { primary: "#6e7480", accent: "#ff9f2e", accent2: "#ff3a3a", eyes: "#ff9f2e" },
    { primary: "#e8eaf0", accent: "#4a90d9", accent2: "#e8437a", eyes: "#4a90d9" },
    { primary: "#c9975a", accent: "#7de24a", accent2: "#ff5470", eyes: "#7de24a" },
    { primary: "#3f4652", accent: "#9a5fff", accent2: "#ff2e2e", eyes: "#9a5fff" },
  ],
  alien: [
    { primary: "#8fd648", accent: "#141018", accent2: "#c7f08a", eyes: "#141018" },
    { primary: "#b9bcc9", accent: "#0c0c12", accent2: "#e2e4ee", eyes: "#0c0c12" },
    { primary: "#a86ad8", accent: "#180c22", accent2: "#d9b3f2", eyes: "#180c22" },
    { primary: "#5fc9c9", accent: "#0c1a1c", accent2: "#b3ecec", eyes: "#0c1a1c" },
  ],
  zombie: [
    { primary: "#a9c46c", accent: "#4a5d33", accent2: "#d7e6ac", eyes: "#e8e4d8" },
    { primary: "#9aa4ac", accent: "#4c545c", accent2: "#d9e0e6", eyes: "#e8e8e2" },
    { primary: "#a08ab4", accent: "#55446a", accent2: "#d9cce8", eyes: "#ece8f2" },
  ],
  skull: [
    { primary: "#f2ede2", accent: "#221d18", accent2: "#7de24a", eyes: "#7de24a" },
    { primary: "#f2e6da", accent: "#2b1d18", accent2: "#ff4a3a", eyes: "#ff4a3a" },
    { primary: "#eef0f2", accent: "#1d2228", accent2: "#4ad6ff", eyes: "#4ad6ff" },
    { primary: "#3a3540", accent: "#17131c", accent2: "#ffb02e", eyes: "#ffb02e" },
  ],
  oni: [
    { primary: "#d8342e", accent: "#f7c948", accent2: "#241612", eyes: "#ffd84a" },
    { primary: "#3a5fd8", accent: "#d9d9e8", accent2: "#16162a", eyes: "#7de2ff" },
    { primary: "#3a9a52", accent: "#f2d9a4", accent2: "#14261a", eyes: "#ffd23e" },
    { primary: "#3a3440", accent: "#c9c2d4", accent2: "#120e18", eyes: "#ff4a3a" },
  ],
  pumpkin: [
    { primary: "#f5871f", accent: "#6a9a2a", accent2: "#ffd94a", eyes: "#ffd94a" },
    { primary: "#ece6d9", accent: "#7aa43a", accent2: "#a4e8ff", eyes: "#a4e8ff" },
    { primary: "#9aa43a", accent: "#4a7a1e", accent2: "#ff9f2e", eyes: "#ff9f2e" },
  ],
  ghost: [
    { primary: "#eef3fb", accent: "#8fa7d0", accent2: "#ffffff", eyes: "#2c3350" },
    { primary: "#e2f7ee", accent: "#6ac9a4", accent2: "#d9fff2", eyes: "#1e4a3a" },
    { primary: "#efe6fb", accent: "#a98fd0", accent2: "#ffffff", eyes: "#3a2c50" },
    { primary: "#fbf4dd", accent: "#d0b96a", accent2: "#fff7d9", eyes: "#4a3c1a" },
  ],
  ninja: [
    { primary: "#333a4c", accent: "#e8b98a", accent2: "#e23c3c", eyes: "#2a2018" },
    { primary: "#23252e", accent: "#c99a6a", accent2: "#e8b02e", eyes: "#1a140e" },
    { primary: "#5a2c34", accent: "#e8c9a4", accent2: "#2b2b34", eyes: "#2c1c14" },
    { primary: "#2c4438", accent: "#d9a87c", accent2: "#e8632e", eyes: "#201810" },
  ],
  slime: [
    { primary: "#4fd8a0", accent: "#baf5dd", accent2: "#ffffff", eyes: "#1e4a3a" },
    { primary: "#4fa8e8", accent: "#b3dcf7", accent2: "#ffffff", eyes: "#1a3a55" },
    { primary: "#f27ab0", accent: "#fcc9e2", accent2: "#ffffff", eyes: "#55203a" },
    { primary: "#9a6ae8", accent: "#d4baf7", accent2: "#ffffff", eyes: "#33205a" },
    { primary: "#e8d23a", accent: "#f7ecad", accent2: "#ffffff", eyes: "#4c4210" },
  ],
};

type NamePair = readonly [en: string, ru: string];

const NAMES: Record<AvatarKind, readonly NamePair[]> = {
  cat: [
    ["Barsik", "Барсик"], ["Coal", "Уголёк"], ["Snowball", "Снежок"],
    ["Tom", "Том"], ["Murka", "Мурка"], ["Leo", "Лео"],
    ["Biscuit", "Бисквит"], ["Salem", "Салем"], ["Marble", "Мрамор"],
    ["Ginger", "Рыжик"], ["Boss", "Босс"], ["Mittens", "Варежка"],
  ],
  fox: [
    ["Alice", "Алиса"], ["Rusty", "Рыжий"], ["Vixen", "Плутовка"],
    ["Blizzard", "Метель"], ["Spark", "Искра"], ["Silver", "Серебро"],
    ["Dune", "Дюна"], ["Scout", "Скаут"], ["Sly", "Хитрец"],
    ["Foxy", "Фокси"], ["Tails", "Хвостик"], ["Ruby", "Руби"],
  ],
  panda: [
    ["Po", "По"], ["Bamboo", "Бамбук"], ["Mochi", "Моти"],
    ["YinYang", "Иньян"], ["Boba", "Боба"], ["Dumpling", "Пельмень"],
    ["Pan", "Пан"], ["Kuma", "Кума"], ["Milky", "Милки"], ["Oreo", "Орео"],
  ],
  frog: [
    ["Hopper", "Прыгун"], ["Croak", "Квак"], ["Lily", "Лилия"],
    ["Bogg", "Болотник"], ["Tad", "Головастик"], ["Quentin", "Квентин"],
    ["Puddle", "Лужа"], ["Moss", "Мох"], ["Jumpy", "Попрыгун"], ["Toad", "Жаба"],
  ],
  bear: [
    ["Bruno", "Бруно"], ["Grizzly", "Гризли"], ["Honey", "Мёд"],
    ["Kodiak", "Кадьяк"], ["Umka", "Умка"], ["Baloo", "Балу"],
    ["Winter", "Зима"], ["Boris", "Борис"], ["Teddy", "Тедди"], ["Shaggy", "Лохматый"],
  ],
  tiger: [
    ["Khan", "Хан"], ["Stripes", "Полоскун"], ["Rajah", "Раджа"],
    ["Blaze", "Пламя"], ["Sher", "Шерхан"], ["Tigra", "Тигра"],
    ["Amur", "Амур"], ["Frost", "Мороз"], ["Shadow", "Тень"], ["Fang", "Клык"],
  ],
  owl: [
    ["Hoot", "Ух"], ["Archimedes", "Архимед"], ["Sage", "Мудрец"],
    ["Echo", "Эхо"], ["Snowy", "Снежана"], ["Merlin", "Мерлин"],
    ["Twilight", "Сумрак"], ["Blink", "Моргун"], ["Professor", "Профессор"], ["Night", "Ночка"],
  ],
  bunny: [
    ["Thumper", "Топотун"], ["Snowy", "Снежка"], ["Clover", "Клевер"],
    ["Binky", "Бинки"], ["Carrot", "Морковка"], ["Fluff", "Пух"],
    ["Hazel", "Орешек"], ["Pepper", "Перчик"], ["Cotton", "Хлопок"], ["Skip", "Скок"],
  ],
  shiba: [
    ["Doge", "Доге"], ["Hachi", "Хати"], ["Kabo", "Кабо"],
    ["Suki", "Суки"], ["Mame", "Маме"], ["Yukio", "Юкио"],
    ["Taro", "Таро"], ["Koro", "Коро"], ["Sora", "Сора"], ["Chibi", "Чиби"],
  ],
  penguin: [
    ["Pingu", "Пингу"], ["Tux", "Смокинг"], ["Waddle", "Топтыга"],
    ["Frosty", "Морозко"], ["Pebble", "Галька"], ["Gustav", "Густав"],
    ["Chilly", "Холодок"], ["Iceberg", "Айсберг"], ["Flip", "Флип"], ["Nero", "Неро"],
  ],
  axolotl: [
    ["Axel", "Аксель"], ["Bubbles", "Пузырик"], ["Coral", "Коралл"],
    ["Mango", "Манго"], ["Peachy", "Персик"], ["Gilly", "Жабрик"],
    ["Rosie", "Рози"], ["Lotl", "Лотль"], ["Neo", "Нео"], ["Splash", "Всплеск"],
  ],
  unicorn: [
    ["Sparkle", "Искорка"], ["Rainbow", "Радуга"], ["Star", "Звёздочка"],
    ["Misty", "Дымка"], ["Aurora", "Аврора"], ["Comet", "Комета"],
    ["Magic", "Магия"], ["Crystal", "Кристалл"], ["Dream", "Мечта"], ["Moonbeam", "Лучик"],
  ],
  robot: [
    ["Bolt", "Болт"], ["Circuit", "Схема"], ["Vector", "Вектор"],
    ["Gear", "Шестерня"], ["Chip", "Чип"], ["Astro", "Астро"],
    ["Servo", "Серво"], ["Titan", "Титан"], ["Pixel", "Пиксель"], ["Omega", "Омега"],
  ],
  alien: [
    ["Zorg", "Зорг"], ["Nebula", "Небула"], ["Quasar", "Квазар"],
    ["Orbit", "Орбита"], ["Glorp", "Глорп"], ["Xeno", "Ксено"],
    ["Cosmo", "Космо"], ["Vega", "Вега"], ["Plasma", "Плазма"], ["Zim", "Зим"],
  ],
  zombie: [
    ["Lurch", "Ковыляка"], ["Moldy", "Плесень"], ["Graves", "Могила"],
    ["Rot", "Гниль"], ["Shambles", "Шаркун"], ["Brains", "Мозги"],
    ["Grim", "Мрак"], ["Stitch", "Стежок"], ["Crypt", "Склеп"], ["Doom", "Рок"],
  ],
  skull: [
    ["Bones", "Кости"], ["Reaper", "Жнец"], ["Marrow", "Мосол"],
    ["Grin", "Оскал"], ["Hollow", "Пустой"], ["Rattle", "Гремучий"],
    ["Dusty", "Прах"], ["Phantom", "Фантом"], ["Calcium", "Кальций"], ["Mort", "Морт"],
  ],
  oni: [
    ["Akuma", "Акума"], ["Raijin", "Райдзин"], ["Kage", "Кагэ"],
    ["Yasha", "Якша"], ["Goro", "Горо"], ["Fudo", "Фудо"],
    ["Ryu", "Рю"], ["Enma", "Энма"], ["Tengu", "Тэнгу"], ["Kuro", "Куро"],
  ],
  pumpkin: [
    ["Jack", "Джек"], ["Gourdon", "Тыквич"], ["Ember", "Огонёк"],
    ["Patch", "Грядка"], ["Cinder", "Зола"], ["Wick", "Фитиль"],
    ["Squash", "Кабачок"], ["Lantern", "Фонарь"], ["Autumn", "Осень"], ["Spooky", "Жуть"],
  ],
  ghost: [
    ["Boo", "Бу"], ["Wisp", "Дымок"], ["Whisper", "Шёпот"],
    ["Gloom", "Хмарь"], ["Spirit", "Дух"], ["Haze", "Марево"],
    ["Wraith", "Призрак"], ["Spooks", "Страшила"], ["Mist", "Туман"], ["Vapor", "Пар"],
  ],
  ninja: [
    ["Hanzo", "Хандзо"], ["Shade", "Тень"], ["Kunai", "Кунай"],
    ["Smoke", "Дым"], ["Viper", "Гадюка"], ["Raven", "Ворон"],
    ["Storm", "Гроза"], ["Blade", "Клинок"], ["Silent", "Тихий"], ["Kiri", "Кири"],
  ],
  slime: [
    ["Goo", "Гуу"], ["Jelly", "Желе"], ["Blob", "Капля"],
    ["Sticky", "Липучка"], ["Wobble", "Дрожжик"], ["Ooze", "Слизень"],
    ["Bounce", "Прыгучка"], ["Gum", "Жвачка"], ["Drip", "Капель"], ["Splat", "Шлёп"],
  ],
  human: [
    ["Viktor", "Виктор"], ["Mia", "Мия"], ["Dmitri", "Дмитрий"],
    ["Elena", "Елена"], ["Igor", "Игорь"], ["Sasha", "Саша"],
    ["Boris", "Борис"], ["Anya", "Аня"], ["Max", "Макс"],
    ["Nina", "Нина"], ["Oleg", "Олег"], ["Vera", "Вера"],
    ["Ivan", "Иван"], ["Katya", "Катя"], ["Pavel", "Павел"],
    ["Dasha", "Даша"], ["Roman", "Роман"], ["Alisa", "Алиса"],
    ["Timur", "Тимур"], ["Sonya", "Соня"], ["Gleb", "Глеб"],
    ["Rita", "Рита"], ["Artur", "Артур"], ["Zhenya", "Женя"],
    ["Denis", "Денис"], ["Olya", "Оля"], ["Fedor", "Фёдор"], ["Marta", "Марта"],
  ],
};

const ROMAN = ["", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"];

function nameFor(kind: AvatarKind, index: number): { en: string; ru: string } {
  const pool = NAMES[kind];
  const [en, ru] = pool[index % pool.length]!;
  const cycle = Math.floor(index / pool.length);
  const suffix = cycle > 0 ? ` ${ROMAN[cycle + 1] ?? cycle + 1}` : "";
  return { en: `${en}${suffix}`, ru: `${ru}${suffix}` };
}

/** Сколько вариаций генерируем на вид (плюс кураторские пресеты сверху). */
const GEN_COUNTS: ReadonlyArray<readonly [AvatarKind, number]> = [
  ["human", 55],
  ["cat", 11], ["fox", 11], ["panda", 11], ["frog", 11],
  ["bear", 11], ["tiger", 11], ["owl", 11], ["bunny", 11],
  ["shiba", 11], ["penguin", 11], ["axolotl", 11], ["unicorn", 11],
  ["robot", 10], ["skull", 10], ["oni", 10],
  ["alien", 9], ["zombie", 9], ["pumpkin", 9],
  ["ghost", 9], ["ninja", 9], ["slime", 9],
];

const HUMAN_SKINS = [
  "#f7dcc4", "#f2c9a4", "#edbd8e", "#d9a066",
  "#c68642", "#a86a3c", "#8d5a30", "#6b4423",
] as const;

const HUMAN_HAIR_COLORS = [
  "#181209", "#3a2c1e", "#6b4a2c", "#a86a32", "#c0561e",
  "#d8b04a", "#d8d4d0", "#ff79b0", "#19d3c5", "#6f4fd8",
] as const;

const HUMAN_EYE_COLORS = [
  "#3f6f8f", "#4a6741", "#3d2314", "#2c1810", "#5a4a8f", "#52708a",
] as const;

const HUMAN_HAIR_STYLES: readonly HumanHairStyle[] = [
  "mohawk", "afro", "buns", "spiky", "long", "braids", "granny", "bald",
];

const pick = <T,>(arr: readonly T[], rnd: () => number): T =>
  arr[Math.floor(rnd() * arr.length)]!;

function generateHumans(count: number, rnd: () => number): AvatarFacePreset[] {
  const out: AvatarFacePreset[] = [];
  const seen = new Set<string>();
  let attempts = 0;
  while (out.length < count && attempts < count * 60) {
    attempts += 1;
    const skin = pick(HUMAN_SKINS, rnd);
    const hair = pick(HUMAN_HAIR_COLORS, rnd);
    const style = pick(HUMAN_HAIR_STYLES, rnd);
    const eyes = pick(HUMAN_EYE_COLORS, rnd);
    const beard = style !== "granny" && style !== "buns" && rnd() < 0.28;
    const glasses = rnd() < 0.18;
    const freckles = rnd() < 0.25;
    const earrings = rnd() < 0.22;
    const key = [skin, hair, style, eyes, beard, glasses, freckles, earrings].join("|");
    if (seen.has(key)) continue;
    seen.add(key);
    const i = out.length;
    const traits: HumanTraits = {
      hair: style,
      ...(beard ? { beard: true } : {}),
      ...(glasses ? { glasses: true } : {}),
      ...(freckles ? { freckles: true } : {}),
      ...(earrings ? { earrings: true } : {}),
    };
    out.push({
      id: `human-${i + 2}`,
      label: nameFor("human", i),
      kind: "human",
      mood: MOODS[i % MOODS.length]!,
      primary: skin,
      shade: darken(skin, 0.24),
      accent: hair,
      accent2: lighten(hair, 0.28),
      eyes,
      human: traits,
    });
  }
  return out;
}

export function generateAvatarRoster(): AvatarFacePreset[] {
  const out: AvatarFacePreset[] = [];
  GEN_COUNTS.forEach(([kind, count], kindIndex) => {
    const rnd = mulberry32(0xc0ffee + kindIndex * 7919);
    if (kind === "human") {
      out.push(...generateHumans(count, rnd));
      return;
    }
    const palettes = KIND_PALETTES[kind];
    const combos: Array<readonly [Palette, AvatarMood]> = [];
    for (const palette of palettes) {
      for (const mood of MOODS) combos.push([palette, mood]);
    }
    shuffled(combos, rnd)
      .slice(0, count)
      .forEach(([palette, mood], i) => {
        out.push({
          id: `${kind}-${i + 2}`,
          label: nameFor(kind, i),
          kind,
          mood,
          primary: palette.primary,
          shade: palette.shade ?? darken(palette.primary, 0.28),
          accent: palette.accent,
          accent2: palette.accent2,
          eyes: palette.eyes,
        });
      });
  });
  return out;
}
