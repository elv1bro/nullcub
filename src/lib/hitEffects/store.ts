import type { FighterSide } from "@/lib/useHealth";

/** Расширяющееся кольцо по полу (#17). */
export interface GroundShockwave {
  x: number;
  y: number;
  born: number;
  color: string;
  power: number;
}

/** Крупная надпись комментатора (#19). */
export interface AnnouncerCallout {
  text: string;
  born: number;
  tier: "medium" | "heavy" | "ko";
  side: FighterSide;
  color: string;
  secondary: string;
}

/** Состояние комбо (#18). */
export interface ComboState {
  count: number;
  side: FighterSide;
  lastHitAt: number;
}

export interface ScreenFlash {
  color: string;
  alpha: number;
  until: number;
}

export interface ScreenShake {
  intensity: number;
  until: number;
}

/** Замедление / стоп времени (#3, #10). */
export interface TimeFxSegment {
  start: number;
  until: number;
  scale: number;
}

export interface FinisherCam {
  active: boolean;
  until: number;
  focusX: number;
  focusY: number;
  zoom: number;
}

/** Короткий punch-zoom на тяжёлый удар. */
export interface ImpactCam {
  until: number;
  focusX: number;
  focusY: number;
  zoom: number;
}

/** Искры комбо ×5 (canvas, работает и в replay). */
export interface ComboSparkBurst {
  x: number;
  y: number;
  born: number;
  color: string;
  secondary: string;
  power: number;
}

export interface HitEffectStore {
  shake: ScreenShake;
  flash: ScreenFlash | null;
  timeSegments: TimeFxSegment[];
  shockwaves: GroundShockwave[];
  combo: ComboState | null;
  callouts: AnnouncerCallout[];
  finisher: FinisherCam | null;
  impactCam: ImpactCam | null;
  /** До этого момента — invert/impact frames. */
  impactInvertUntil: number;
  comboSparks: ComboSparkBurst[];
}

export function createHitEffectStore(): HitEffectStore {
  return {
    shake: { intensity: 0, until: 0 },
    flash: null,
    timeSegments: [],
    shockwaves: [],
    combo: null,
    callouts: [],
    finisher: null,
    impactCam: null,
    impactInvertUntil: 0,
    comboSparks: [],
  };
}

export const SHOCKWAVE_LIFE_MS = 680;
export const CALLOUT_LIFE_MS = 1400;
/** Длина finisher-камеры после KO — повтор ждёт столько же. */
export const FINISHER_MS = 2200;
export const COMBO_WINDOW_MS = 900;
export const IMPACT_FRAME_MS = 70;
export const IMPACT_CAM_MS = 160;
export const COMBO_SPARK_LIFE_MS = 720;

export const MEDIUM_DAMAGE = 15;
export const HEAVY_DAMAGE = 30;

export function pruneHitEffectStore(store: HitEffectStore, now: number): void {
  store.shockwaves = store.shockwaves.filter(
    (w) => now - w.born < SHOCKWAVE_LIFE_MS,
  );
  store.callouts = store.callouts.filter((c) => now - c.born < CALLOUT_LIFE_MS);
  store.comboSparks = store.comboSparks.filter(
    (s) => now - s.born < COMBO_SPARK_LIFE_MS,
  );
  if (store.flash && now >= store.flash.until) store.flash = null;
  if (store.shake.until <= now) store.shake.intensity = 0;
  store.timeSegments = store.timeSegments.filter((s) => s.until > now);
  if (store.finisher && now >= store.finisher.until) store.finisher = null;
  if (store.impactCam && now >= store.impactCam.until) store.impactCam = null;
  if (store.impactInvertUntil > 0 && now >= store.impactInvertUntil) {
    store.impactInvertUntil = 0;
  }
}
