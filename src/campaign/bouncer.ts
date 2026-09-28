import type { Language } from "@/i18n/types";
import type { FighterColors } from "@/lib/fighterColors";
import { OPPONENT_MAX_HP } from "@/lib/combat";

export type BouncerChapterId =
  | "bard"
  | "knight"
  | "twin"
  | "merchant"
  | "captain"
  | "boss";

type L10n = Record<Language, string>;

export interface BouncerEnemySpec {
  name: L10n;
  scale: number;
  hp: number;
  colors: FighterColors;
  aiSpeedMult: number;
}

export interface BouncerChapter {
  id: BouncerChapterId;
  order: number;
  title: L10n;
  intro: L10n;
  outro: L10n;
  enemy: BouncerEnemySpec;
}

export const BOUNCER_CAMPAIGN_ID = "bouncer";

export const BOUNCER_CHAPTERS: BouncerChapter[] = [
  {
    id: "bard",
    order: 0,
    title: { ru: "Пьяный бард", en: "Drunk bard" },
    intro: {
      ru: "Бард снова орёт песню про драконов. Трактирщик просит его заткнуть.",
      en: "The bard is screaming another dragon song. The innkeeper wants silence.",
    },
    outro: {
      ru: "Лютня затихла. Следующий дебошир уже в коридоре.",
      en: "The lute goes quiet. The next troublemaker waits in the hall.",
    },
    enemy: {
      name: { ru: "Бард", en: "Bard" },
      scale: 1,
      hp: OPPONENT_MAX_HP,
      colors: { main: "#78716c", secondary: "#57534e" },
      aiSpeedMult: 0.9,
    },
  },
  {
    id: "knight",
    order: 1,
    title: { ru: "Рыцарь-дебошир", en: "Rowdy knight" },
    intro: {
      ru: "Рыцарь в доспехах пытается «защитить честь» кружки.",
      en: "An armored knight defends the honor of his mug.",
    },
    outro: {
      ru: "Доспехи громыхнули о пол. Но в углу кто-то уже шепчет «а можно халяву?»",
      en: "Armor clatters on the floor. Someone in the corner whispers about freebies.",
    },
    enemy: {
      name: { ru: "Рыцарь", en: "Knight" },
      scale: 1.05,
      hp: 1100,
      colors: { main: "#64748b", secondary: "#475569" },
      aiSpeedMult: 1,
    },
  },
  {
    id: "twin",
    order: 2,
    title: { ru: "Близнец-халявщик", en: "Freeloader twin" },
    intro: {
      ru: "Мелкий тип прыгает вокруг и орёт: «я тут просто посидеть!»",
      en: "A tiny guy bounces around yelling he only came to sit.",
    },
    outro: {
      ru: "Халявщик улетел за стойку. В зале уже кто-то другой.",
      en: "The freeloader flies behind the bar. Someone else is already making noise.",
    },
    enemy: {
      name: { ru: "Халявщик", en: "Freeloader" },
      scale: 0.95,
      hp: 1200,
      colors: { main: "#a3e635", secondary: "#65a30d" },
      aiSpeedMult: 1.05,
    },
  },
  {
    id: "merchant",
    order: 3,
    title: { ru: "Торговец без чека", en: "Receiptless merchant" },
    intro: {
      ru: "Купец размахивает мешком монет: «Это была скидка, вышибала!»",
      en: "A merchant waves a coin pouch: «That was a discount, bouncer!»",
    },
    outro: {
      ru: "Мешок звякнул о пол. За дверью уже слышен морской акцент.",
      en: "The pouch hits the floor. A salty accent booms from the doorway.",
    },
    enemy: {
      name: { ru: "Торговец", en: "Merchant" },
      scale: 1,
      hp: 1300,
      colors: { main: "#eab308", secondary: "#ca8a04" },
      aiSpeedMult: 1,
    },
  },
  {
    id: "captain",
    order: 4,
    title: { ru: "Капитан с корабля", en: "Ship captain" },
    intro: {
      ru: "Моряк в шторме шапки орёт про честь команды и бесплатную кружку.",
      en: "A storm-hatted sailor yells about crew honor and a free mug.",
    },
    outro: {
      ru: "Шляпа капитана летит в бочку. Хозяин бара только кивает.",
      en: "The captain's hat sails into a barrel. The innkeeper just nods.",
    },
    enemy: {
      name: { ru: "Капитан", en: "Captain" },
      scale: 1.08,
      hp: 1450,
      colors: { main: "#0ea5e9", secondary: "#0369a1" },
      aiSpeedMult: 1.05,
    },
  },
  {
    id: "boss",
    order: 5,
    title: { ru: "Трактирщик", en: "Innkeeper" },
    intro: {
      ru: "Хозяин бара достаёт швабру. «За всё заплатишь телом, вышибала!»",
      en: "The innkeeper grabs a mop. «You'll pay for everything with your ragdoll body!»",
    },
    outro: {
      ru: "Таверна снова тихая. Ты — легенда вышибалы. Пока не придёт следующий.",
      en: "The tavern is quiet again. You're a bouncer legend—until the next brawl.",
    },
    enemy: {
      name: { ru: "Трактирщик", en: "Innkeeper" },
      scale: 1.12,
      hp: 1600,
      colors: { main: "#92400e", secondary: "#78350f" },
      aiSpeedMult: 1.08,
    },
  },
];

export function getBouncerChapter(id: string): BouncerChapter | undefined {
  return BOUNCER_CHAPTERS.find((c) => c.id === id);
}

export function pickL10n(text: L10n, language: Language): string {
  return text[language] ?? text.en;
}
