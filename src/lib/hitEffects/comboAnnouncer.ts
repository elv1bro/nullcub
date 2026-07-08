import type { Language } from "@/i18n";
import type { FighterColors } from "@/lib/fighterColors";
import type { FighterSide } from "@/lib/useHealth";
import {
  CALLOUT_LIFE_MS,
  COMBO_WINDOW_MS,
  type AnnouncerCallout,
  type HitEffectStore,
} from "./store";

const ANNOUNCER: Record<
  Language,
  { medium: string[]; heavy: string[]; ko: string[] }
> = {
  ru: {
    medium: ["ЖЁСТКО!", "БАХ!", "В ТОЧКУ!", "ОХ!", "НЕПЛОХО!"],
    heavy: ["BRUTAL!", "DOMINATING!", "RAGDOLL RIOT!", "УНИЧТОЖЕН!", "WTF?!"],
    ko: ["FATALITY!", "FLAWLESS!", "GAME OVER!", "НОКАУТ!", "GG!"],
  },
  en: {
    medium: ["BRUTAL!", "POW!", "NICE HIT!", "OOF!", "CONTACT!"],
    heavy: ["DOMINATING!", "BRUTALITY!", "RAGDOLL RIOT!", "OBLITERATED!", "WTF?!"],
    ko: ["FATALITY!", "FLAWLESS!", "FINISH HIM!", "K.O.!", "GG!"],
  },
};

function pickLine(lines: string[], slot: number): string {
  return lines[slot % lines.length] ?? lines[0] ?? "…";
}

export function updateCombo(
  store: HitEffectStore,
  aggressorSide: FighterSide,
  now: number,
): number {
  const prev = store.combo;
  if (
    prev &&
    prev.side === aggressorSide &&
    now - prev.lastHitAt < COMBO_WINDOW_MS
  ) {
    prev.count += 1;
    prev.lastHitAt = now;
    return prev.count;
  }
  store.combo = { count: 1, side: aggressorSide, lastHitAt: now };
  return 1;
}

export function spawnAnnouncer(
  store: HitEffectStore,
  tier: AnnouncerCallout["tier"],
  language: Language,
  slot: number,
  now: number,
  side: FighterSide,
  colors: FighterColors,
): void {
  const pool = ANNOUNCER[language][tier];
  store.callouts.push({
    text: pickLine(pool, slot),
    born: now,
    tier,
    side,
    color: colors.main,
    secondary: colors.secondary,
  });
  if (store.callouts.length > 3) {
    store.callouts.splice(0, store.callouts.length - 3);
  }
}

export function comboLabel(count: number, language: Language): string {
  if (count < 2) return "";
  return language === "ru" ? `×${count} КОМБО!` : `×${count} COMBO!`;
}

export { ANNOUNCER, CALLOUT_LIFE_MS };
