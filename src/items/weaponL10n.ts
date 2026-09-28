/** Локализованные имена арена-оружия (каталог / лаб). */

export const WEAPON_NAMES: Record<
  string,
  { en: string; ru: string }
> = {
  "frying-pan": { en: "Frying Pan", ru: "Сковорода" },
  spear: { en: "Spear", ru: "Копьё" },
  "chain-flail": { en: "Chain Flail", ru: "Кистень" },
  torch: { en: "Torch", ru: "Факел" },
  sword: { en: "Sword", ru: "Меч" },
  taser: { en: "Taser", ru: "Тазер" },
  bat: { en: "Bat", ru: "Бита" },
  crowbar: { en: "Crowbar", ru: "Лом" },
  katana: { en: "Katana", ru: "Катана" },
  dagger: { en: "Dagger", ru: "Кинжал" },
  hammer: { en: "Hammer", ru: "Молот" },
  axe: { en: "Axe", ru: "Топор" },
  mace: { en: "Mace", ru: "Булава" },
  whip: { en: "Whip", ru: "Кнут" },
  nunchaku: { en: "Nunchaku", ru: "Нунчаки" },
  pitchfork: { en: "Pitchfork", ru: "Вилы" },
  trident: { en: "Trident", ru: "Трезубец" },
  "bo-staff": { en: "Bo Staff", ru: "Бо" },
  "golf-club": { en: "Golf Club", ru: "Клюшка" },
  pipe: { en: "Pipe", ru: "Труба" },
  brick: { en: "Brick", ru: "Кирпич" },
  bottle: { en: "Bottle", ru: "Бутылка" },
  chainsaw: { en: "Toy Chainsaw", ru: "Бензопила-игрушка" },
  "stun-baton": { en: "Stun Baton", ru: "Шокер-дубинка" },
  "cattle-prod": { en: "Cattle Prod", ru: "Электропогонялка" },
  "fire-extinguisher": { en: "Fire Extinguisher", ru: "Огнетушитель" },
  "traffic-cone": { en: "Traffic Cone", ru: "Конус" },
  plunger: { en: "Plunger", ru: "Вантуз" },
  umbrella: { en: "Umbrella", ru: "Зонт" },
  scythe: { en: "Scythe", ru: "Коса" },
  "morning-star": { en: "Morning Star", ru: "Моргенштерн" },
  "las-saber": { en: "Las Saber", ru: "Лас-сабля" },
  wrench: { en: "Wrench", ru: "Ключ" },
  "frying-spatula": { en: "Spatula", ru: "Лопатка" },
  banjo: { en: "Banjo", ru: "Банджо" },
  shotput: { en: "Shot Put", ru: "Ядро" },
};

export function weaponDisplayName(
  id: string,
  lang: "en" | "ru",
  fallback?: string,
): string {
  const row = WEAPON_NAMES[id];
  if (!row) return fallback ?? id;
  return lang === "ru" ? row.ru : row.en;
}
