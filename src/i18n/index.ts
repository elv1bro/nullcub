import en from "./locales/en";
import ru from "./locales/ru";
import type { Language, LocaleStrings } from "./types";

export type { Language, LocaleStrings };

const locales: Record<Language, LocaleStrings> = { en, ru };

export function getLocale(lang: Language): LocaleStrings {
  return locales[lang];
}

export { en, ru };
