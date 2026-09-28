export interface FighterColors {
  main: string;
  secondary: string;
}

export const PLAYER_COLORS: FighterColors = {
  main: "#38bdf8",
  secondary: "#0284c7",
};

export const OPPONENT_COLORS: FighterColors = {
  main: "#f87171",
  secondary: "#b91c1c",
};

/** Палитра слотов 0..3 для лобби / dedicated N. */
export const SLOT_COLORS: FighterColors[] = [
  PLAYER_COLORS,
  OPPONENT_COLORS,
  { main: "#a78bfa", secondary: "#6d28d9" },
  { main: "#34d399", secondary: "#047857" },
];

export function colorsForSlot(index: number): FighterColors {
  return SLOT_COLORS[index % SLOT_COLORS.length] ?? PLAYER_COLORS;
}

export function colorsForSide(side: "player" | "opponent"): FighterColors {
  return side === "player" ? PLAYER_COLORS : OPPONENT_COLORS;
}

/** Текст урона: «-20 ♥» */
export function formatHeartDamage(amount: number): string {
  return `-${Math.max(1, Math.round(amount))} ♥`;
}

/** Текст запаса сердец */
export function formatHeartCount(hearts: number): string {
  return `${Math.ceil(hearts)} ♥`;
}
