import type { FighterSide } from "@/lib/useHealth";
import {
  BANTER_COOLDOWN_MS,
  BANTER_MIN_DAMAGE,
  BANTER_SPAWN_CHANCE,
  MATURE_SPICY_POOL_CHANCE,
} from "@/lib/banterConfig";
import { enBanterSafe, enBanterSpicy } from "./en";
import { ruBanterSafe, ruBanterSpicy } from "./ru";
import { BANTER_POOL_SIZE } from "./buildPool";

export type BanterPool = { player: string[]; opponent: string[] };

const pools = {
  en: { safe: enBanterSafe, spicy: enBanterSpicy },
  ru: { safe: ruBanterSafe, spicy: ruBanterSpicy },
} as const;

export function getBanterPool(
  language: "en" | "ru",
  mature: boolean,
  side: FighterSide,
  roll = Math.random(),
): string[] {
  const set = pools[language];
  const useSpicy = mature && roll < MATURE_SPICY_POOL_CHANCE;
  return useSpicy ? set.spicy[side] : set.safe[side];
}

/** @deprecated — используй pickBanterLine */
export function getBanterLines(
  language: "en" | "ru",
  mature: boolean,
  side: FighterSide,
): string[] {
  return [...getBanterPool(language, mature, side)];
}

let lastBanterLine = "";

export function pickBanterLine(
  language: "en" | "ru",
  mature: boolean,
  side: FighterSide,
): string {
  const spicyRoll = Math.random();
  const pool = getBanterPool(language, mature, side, spicyRoll);
  if (pool.length === 0) return "…";

  let line = pool[Math.floor(Math.random() * pool.length)]!;
  for (let i = 0; i < 5 && line === lastBanterLine && pool.length > 1; i++) {
    line = pool[Math.floor(Math.random() * pool.length)]!;
  }
  lastBanterLine = line;
  return line;
}

export function shouldSpawnBanter(
  damage: number,
  now: number,
  lastAt: number,
  roll = Math.random(),
): boolean {
  if (damage < BANTER_MIN_DAMAGE) return false;
  if (now - lastAt < BANTER_COOLDOWN_MS) return false;
  return roll < BANTER_SPAWN_CHANCE;
}

export { pools as banterPools, BANTER_COOLDOWN_MS, BANTER_POOL_SIZE };
