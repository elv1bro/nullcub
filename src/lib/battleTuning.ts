/** Общие константы боя — гравитация, скорости, способности. */

export const BATTLE_GRAVITY = {
  x: 0,
  y: 1 / 20,
  scale: 1 / 1_000,
} as const;

export const PLAYER_MOVE_SPEED = 40;
/** AI базовые скорости — от той же шкалы, что и игрок. */
export const AI_APPROACH_SPEED = PLAYER_MOVE_SPEED;
export const AI_LUNGE_SPEED = 52;
export const AI_STRAFE_SPEED = PLAYER_MOVE_SPEED;
export const AI_CIRCLE_SPEED = 34;
export const KNOCKBACK_SPEED = -56;
export const MAX_BODY_SPEED = 52;

/** После спавна ragdoll «успокаивается» — без урона и knockback. */
export const BATTLE_SPAWN_GRACE_MS = 700;

/** Первые секунды боя — только удары, без хватания. */
export const BATTLE_OPENING_BRAWL_MS = 2500;

/** Расстояние между бойцами при спавне (центр ± spread). */
export const BATTLE_SPAWN_SPREAD = 140;

/**
 * Пауза после KO перед повтором/recap.
 * Должна покрывать finisher-камеру, иначе повтор перекрывает зум.
 */
export const BATTLE_RECAP_DELAY_MS = 2200;

/** Временно выключить хват (Q/E и AI grab) — пока драка без захватов. */
export const GRAB_ENABLED = false;

/**
 * Автоподбор и сброс арена-оружия (не fighter-grab).
 * Работает независимо от GRAB_ENABLED.
 */
export const WEAPON_HOLD_ENABLED = true;
/** Радиус автоподбора до рукояти оружия (px). */
export const AUTO_PICKUP_RANGE = 96;
/** Пауза между автоподборами одной рукой. */
export const AUTO_PICKUP_COOLDOWN_MS = 350;

export function battleSpawnPositions(arenaSize: number): {
  playerX: number;
  opponentX: number;
  y: number;
} {
  const center = arenaSize / 2;
  return {
    playerX: center - BATTLE_SPAWN_SPREAD,
    opponentX: center + BATTLE_SPAWN_SPREAD,
    y: center,
  };
}

/** Лимит боя: после него включается sudden death. */
export const BATTLE_TIME_LIMIT_MS = 90_000;
/** Sudden death: каждые N мс урон растёт на STEP (25%). */
export const SUDDEN_DEATH_STEP = 0.25;
export const SUDDEN_DEATH_STEP_MS = 10_000;
/** Жёсткий тайм-аут: бой заканчивается, победа по оставшемуся HP (равенство — ничья). */
export const BATTLE_HARD_TIMEOUT_MS = 180_000;

/** Множитель урона по прошедшему времени боя (1 до лимита, дальше лестница). */
export function suddenDeathMultiplier(elapsedMs: number): number {
  const over = elapsedMs - BATTLE_TIME_LIMIT_MS;
  if (over < 0) return 1;
  return 1 + SUDDEN_DEATH_STEP * (Math.floor(over / SUDDEN_DEATH_STEP_MS) + 1);
}

/** KO: тихий разлёт частей. */
export const KO_SCATTER_SPEED_MIN = 8;
export const KO_SCATTER_SPEED_MAX = 22;

/** Рывок: ×1.8 к скорости ходьбы на 2 с, перезарядка 10 с. */
export const DASH_COOLDOWN_MS = 10_000;
export const DASH_SPEED_MULT = 1.8;
export const DASH_DURATION_MS = 2000;

/** Переворот: резкий набор угловой скорости. */
export const FLIP_COOLDOWN_MS = 600;
export const FLIP_ANGULAR_VEL = 1.1;

/** Reset: вернуть T-позу за 1 с. */
export const RESET_DURATION_MS = 1000;
export const RESET_COOLDOWN_MS = 8000;

/** Стойка: устойчивость ~1.5 с — меньше кручения и отбрасывания. */
export const BRACE_DURATION_MS = 1500;
export const BRACE_COOLDOWN_MS = 15_000;
export const BRACE_KNOCKBACK_MULT = 0.42;

/** @deprecated use BRACE_* */
export const FREEZE_DURATION_MS = BRACE_DURATION_MS;
/** @deprecated use BRACE_* */
export const FREEZE_COOLDOWN_MS = BRACE_COOLDOWN_MS;
