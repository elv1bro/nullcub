import { BANTER_POOL_SIZE } from "./buildPool";
import * as seeds from "./seeds/ru";

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

const clean = (arr: readonly string[]): string[] =>
  arr.map((s) => s.trim()).filter(Boolean);

/**
 * Пул из готовых фраз — без склейки. Все фразы попадают как есть.
 * `hot` (короткие выкрики) добивают пул до нужного размера, поэтому звучат чаще.
 */
function buildRuSide(
  core: readonly string[],
  hot: readonly string[],
  size = BANTER_POOL_SIZE,
): string[] {
  const base = [...new Set(clean(core))].sort((a, b) => hash(a) - hash(b));
  if (base.length >= size) return base.slice(0, size);

  const hotList = [...new Set(clean(hot))];
  const out = base.slice();
  for (let i = 0; out.length < size; i++) {
    out.push(hotList[i % hotList.length]!);
  }
  return out;
}

export const ruBanterSafe = {
  player: buildRuSide(seeds.ruSafePlayerCore, seeds.ruSafePlayerHot),
  opponent: buildRuSide(seeds.ruSafeOpponentCore, seeds.ruSafeOpponentHot),
};

export const ruBanterSpicy = {
  player: buildRuSide(seeds.ruSpicyPlayerCore, seeds.ruSpicyPlayerHot),
  opponent: buildRuSide(seeds.ruSpicyOpponentCore, seeds.ruSpicyOpponentHot),
};
