import type { ItemDef } from "./registry";

const BASE_DISARM_CHANCE = 0.01;

export function computeDisarmChance(
  item: ItemDef,
  holderToughness: number,
): number {
  const toughness = 1 + holderToughness + item.toughnessBonus;
  return (BASE_DISARM_CHANCE * item.dropChanceMult) / toughness;
}

export function rollDisarm(chance: number, rng = Math.random): boolean {
  return rng() < chance;
}
