/** Параметрические пресеты бота — без ML, калибруются симуляциями. */

export type AiDifficultyId = "easy" | "normal" | "hard" | "boss";

export interface AiProfile {
  id: AiDifficultyId;
  /** Множитель базовых скоростей движения (legacy aiSpeedMult). */
  speedMult: number;
  /** Задержка перед сменой тактики / grab. */
  reactionDelayMs: number;
  /** Кулдаун рывка к игроку. */
  lungeCooldownMs: number;
  /** Дистанция рывка. */
  lungeRange: number;
  /** Шанс ошибиться (случайный strafe flip). 0..1 */
  mistakeRate: number;
  /** Разброс направления движения. 0..1 */
  aimNoise: number;
  /** Макс. дистанция для grab. */
  grabRange: number;
  /** Шанс короткого импульса хвата при срабатывании кулдауна. */
  grabChance: number;
  /** Длительность нажатия Q/E — короткий импульс, не удержание. */
  grabHoldMs: number;
  /** Пауза между попытками хвата. */
  grabCooldownMs: number;
  useDash: boolean;
  dashCooldownMs: number;
  dashDurationMs: number;
  useFlip: boolean;
  flipCooldownMs: number;
  useBrace: boolean;
  braceCooldownMs: number;
  /** Целевой win-rate бота в offline-симе (для отчёта). */
  targetBotWinRate: number;
}

/** Текущий бот ≈ normal (~20% побед бота vs средний игрок). */
export const AI_PROFILES: Record<AiDifficultyId, AiProfile> = {
  easy: {
    id: "easy",
    speedMult: 0.62,
    reactionDelayMs: 420,
    lungeCooldownMs: 1400,
    lungeRange: 220,
    mistakeRate: 0.22,
    aimNoise: 0.35,
    grabRange: 0,
    grabChance: 0,
    grabHoldMs: 0,
    grabCooldownMs: 0,
    useDash: false,
    dashCooldownMs: 99_000,
    dashDurationMs: 0,
    useFlip: false,
    flipCooldownMs: 99_000,
    useBrace: false,
    braceCooldownMs: 99_000,
    targetBotWinRate: 0.08,
  },
  normal: {
    id: "normal",
    speedMult: 0.95,
    reactionDelayMs: 200,
    lungeCooldownMs: 950,
    lungeRange: 270,
    mistakeRate: 0.1,
    aimNoise: 0.14,
    grabRange: 100,
    grabChance: 0.22,
    grabHoldMs: 200,
    grabCooldownMs: 5000,
    useDash: false,
    dashCooldownMs: 99_000,
    dashDurationMs: 0,
    useFlip: false,
    flipCooldownMs: 99_000,
    useBrace: false,
    braceCooldownMs: 99_000,
    targetBotWinRate: 0.2,
  },
  hard: {
    id: "hard",
    speedMult: 1.16,
    reactionDelayMs: 95,
    lungeCooldownMs: 650,
    lungeRange: 315,
    mistakeRate: 0.03,
    aimNoise: 0.045,
    grabRange: 110,
    grabChance: 0.32,
    grabHoldMs: 240,
    grabCooldownMs: 4000,
    useDash: true,
    dashCooldownMs: 9000,
    dashDurationMs: 1600,
    useFlip: true,
    flipCooldownMs: 900,
    useBrace: false,
    braceCooldownMs: 99_000,
    targetBotWinRate: 0.38,
  },
  boss: {
    id: "boss",
    speedMult: 1.32,
    reactionDelayMs: 60,
    lungeCooldownMs: 520,
    lungeRange: 335,
    mistakeRate: 0.012,
    aimNoise: 0.02,
    grabRange: 120,
    grabChance: 0.42,
    grabHoldMs: 280,
    grabCooldownMs: 3500,
    useDash: true,
    dashCooldownMs: 7000,
    dashDurationMs: 2000,
    useFlip: true,
    flipCooldownMs: 650,
    useBrace: true,
    braceCooldownMs: 14_000,
    targetBotWinRate: 0.48,
  },
};

export function getAiProfile(id: AiDifficultyId): AiProfile {
  return AI_PROFILES[id];
}

/** Главы кампании → пресет сложности (плавный рост, не hard со 2-й главы). */
export function campaignAiProfile(chapterOrder: number): AiProfile {
  if (chapterOrder <= 0) return AI_PROFILES.easy;
  if (chapterOrder <= 2) return AI_PROFILES.normal;
  if (chapterOrder <= 4) return AI_PROFILES.hard;
  return AI_PROFILES.boss;
}

export const AI_DIFFICULTY_ORDER: AiDifficultyId[] = [
  "easy",
  "normal",
  "hard",
  "boss",
];
