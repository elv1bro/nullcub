import type { Language } from "@/i18n";

export interface EscapeQuip {
  text: string;
  born: number;
  side: "left" | "right";
}

const PHRASES: Record<Language, string[]> = {
  ru: [
    "GO GO GO!",
    "ДАВАЙ!",
    "РВИ!",
    "ЕЩЁ!",
    "НА-НА!",
    "ВПЕРЁД!",
    "А ну!",
    "Жми!",
    "Раз-два!",
    "Хватай!",
  ],
  en: [
    "GO GO GO!",
    "BREAK!",
    "YEAH!",
    "PUSH!",
    "NOW!",
    "LET'S GO!",
    "C'MON!",
    "RIP IT!",
    "ALMOST!",
    "FREEDOM!",
  ],
};

export function spawnEscapeQuip(
  quips: EscapeQuip[],
  language: Language,
  now: number,
  slot: number,
): void {
  const pool = PHRASES[language];
  const text = pool[slot % pool.length] ?? "GO!";
  quips.push({
    text,
    born: now,
    side: slot % 2 === 0 ? "left" : "right",
  });
  if (quips.length > 6) quips.splice(0, quips.length - 6);
}

export function pruneEscapeQuips(quips: EscapeQuip[], now: number): EscapeQuip[] {
  return quips.filter((q) => now - q.born < 900);
}
