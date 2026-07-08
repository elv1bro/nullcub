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

export interface HitEffectStore {
  shake: ScreenShake;
  flash: ScreenFlash | null;
  timeSegments: TimeFxSegment[];
  shockwaves: GroundShockwave[];
  combo: ComboState | null;
  callouts: AnnouncerCallout[];
  finisher: FinisherCam | null;
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
  };
}

export const SHOCKWAVE_LIFE_MS = 680;
export const CALLOUT_LIFE_MS = 1400;
export const FINISHER_MS = 2200;
export const COMBO_WINDOW_MS = 900;

export const MEDIUM_DAMAGE = 15;
export const HEAVY_DAMAGE = 30;

export function pruneHitEffectStore(store: HitEffectStore, now: number): void {
  store.shockwaves = store.shockwaves.filter(
    (w) => now - w.born < SHOCKWAVE_LIFE_MS,
  );
  store.callouts = store.callouts.filter((c) => now - c.born < CALLOUT_LIFE_MS);
  if (store.flash && now >= store.flash.until) store.flash = null;
  if (store.shake.until <= now) store.shake.intensity = 0;
  store.timeSegments = store.timeSegments.filter((s) => s.until > now);
  if (store.finisher && now >= store.finisher.until) store.finisher = null;
}
