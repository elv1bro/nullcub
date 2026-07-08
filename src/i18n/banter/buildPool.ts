const TARGET_PER_SIDE = 250;
const RU_MIN_CYRILLIC_RATIO = 0.28;

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

function expandMemePlaceholders(
  templates: readonly string[],
  memes: readonly string[],
  cap = 120,
): string[] {
  const out: string[] = [];
  for (const tpl of templates) {
    if (!tpl.includes("{m}")) {
      out.push(tpl);
      continue;
    }
    for (let i = 0; i < Math.min(memes.length, cap); i++) {
      out.push(tpl.replaceAll("{m}", memes[i]!));
    }
  }
  return out;
}

/** Доля кириллических букв среди всех букв в строке (0…1). */
export function cyrillicRatio(line: string): number {
  const letters = [...line.matchAll(/\p{L}/gu)].map((m) => m[0]!);
  if (letters.length === 0) return 0;
  const cyr = letters.filter((c) => /\p{Script=Cyrillic}/u.test(c)).length;
  return cyr / letters.length;
}

/** Строка достаточно «русская» для RU-пула (кириллица + без длинных EN-слов). */
export function isRussianBanterLine(line: string): boolean {
  if (cyrillicRatio(line) >= RU_MIN_CYRILLIC_RATIO) return true;
  if (!/\p{Script=Cyrillic}/u.test(line)) return false;
  return !/\b[a-zA-Z]{5,}\b/.test(line);
}

/** Собирает ~250 уникальных фраз из сидов + мем-шаблонов. */
export function buildSidePool(
  core: readonly string[],
  templates: readonly string[],
  count = TARGET_PER_SIDE,
  keepLine: (line: string) => boolean = () => true,
): string[] {
  const out = new Set<string>();

  const add = (line: string) => {
    const t = line.trim();
    if (t && keepLine(t)) out.add(t);
  };

  for (const line of core) add(line);

  for (const tpl of templates) {
    for (const line of core) {
      add(tpl.replace("{x}", line));
      if (out.size >= count * 3) break;
    }
    if (out.size >= count * 3) break;
  }

  let i = 0;
  while (out.size < count * 2 && i < core.length * 6) {
    const a = core[i % core.length]!;
    const b = core[(i * 7 + 3) % core.length]!;
    add(`${a} — ${b}`);
    add(`${a}… ${b}?`);
    i += 1;
  }

  const list = [...out];
  list.sort((x, y) => hash(x) - hash(y));
  return list.slice(0, count);
}

export function buildBanterTier(
  playerCore: readonly string[],
  opponentCore: readonly string[],
  playerTemplates: readonly string[],
  opponentTemplates: readonly string[],
  memes: readonly string[] = [],
  keepLine: (line: string) => boolean = () => true,
): { player: string[]; opponent: string[] } {
  const pTpl = expandMemePlaceholders(playerTemplates, memes);
  const oTpl = expandMemePlaceholders(opponentTemplates, memes);
  return {
    player: buildSidePool(playerCore, pTpl, TARGET_PER_SIDE, keepLine),
    opponent: buildSidePool(opponentCore, oTpl, TARGET_PER_SIDE, keepLine),
  };
}

/** RU-пул: отбрасывает строки с доминирующим английским. */
export function buildBanterTierRu(
  playerCore: readonly string[],
  opponentCore: readonly string[],
  playerTemplates: readonly string[],
  opponentTemplates: readonly string[],
  memes: readonly string[] = [],
): { player: string[]; opponent: string[] } {
  return buildBanterTier(
    playerCore,
    opponentCore,
    playerTemplates,
    opponentTemplates,
    memes,
    isRussianBanterLine,
  );
}

export const BANTER_POOL_SIZE = TARGET_PER_SIDE;
