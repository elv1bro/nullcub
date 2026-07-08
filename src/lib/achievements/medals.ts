export type MedalId =
  | "first_blood"
  | "combo_3"
  | "combo_5"
  | "heavy_hit"
  | "brutal_hit"
  | "knockout"
  | "clutch"
  | "victory"
  | "revenge"
  | "flawless"
  | "bouncer"
  | "workshop";

export interface MedalDef {
  id: MedalId;
  icon: string;
}

export const MEDALS: MedalDef[] = [
  { id: "victory", icon: "🏆" },
  { id: "knockout", icon: "💀" },
  { id: "flawless", icon: "✨" },
  { id: "revenge", icon: "😤" },
  { id: "clutch", icon: "🎯" },
  { id: "bouncer", icon: "🚪" },
  { id: "workshop", icon: "⚗" },
  { id: "first_blood", icon: "🩸" },
  { id: "combo_5", icon: "×5" },
  { id: "combo_3", icon: "×3" },
  { id: "brutal_hit", icon: "🔥" },
  { id: "heavy_hit", icon: "💥" },
];

export const MEDAL_BY_ID = Object.fromEntries(
  MEDALS.map((m) => [m.id, m]),
) as Record<MedalId, MedalDef>;
