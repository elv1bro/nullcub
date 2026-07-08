import type { EmotionId } from "./emotions";

/** Эмоция пресет-аватара в бою (без вебки). */
export function avatarBattleEmotion(
  playerHp: number,
  maxHp: number,
  painFlash: boolean,
  lastHit: "player" | "opponent" | null,
): EmotionId {
  if (painFlash) return "pain";
  if (lastHit === "opponent") return "smile";
  if (playerHp / maxHp < 0.35) return "scared";
  if (lastHit === "player") return "angry";
  return "neutral";
}
