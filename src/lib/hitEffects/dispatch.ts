import type { Language } from "@/i18n";
import type { FighterColors } from "@/lib/fighterColors";
import { playComboSound } from "@/audio";
import type { FighterSide } from "@/lib/useHealth";
import { comboLabel, updateCombo } from "./comboAnnouncer";
import {
  COMBO_WINDOW_MS,
  FINISHER_MS,
  HEAVY_DAMAGE,
  IMPACT_FRAME_MS,
  MEDIUM_DAMAGE,
  type GroundShockwave,
  type HitEffectStore,
} from "./store";

export interface HitEffectContext {
  damage: number;
  contactX: number;
  contactY: number;
  aggressorSide: FighterSide;
  aggressorColor: string;
  aggressorColors: FighterColors;
  arenaHeight: number;
  language: Language;
  slot: number;
  now: number;
}

const HIT_STOP_MS = 55;
const SLOW_MO_MS = 300;
const SLOW_MO_SCALE = 0.38;

function scheduleTimeFx(
  store: HitEffectStore,
  scale: number,
  startAt: number,
  durationMs: number,
): void {
  store.timeSegments.push({
    start: startAt,
    until: startAt + durationMs,
    scale,
  });
  if (store.timeSegments.length > 12) {
    store.timeSegments.splice(0, store.timeSegments.length - 12);
  }
}

function addShake(store: HitEffectStore, intensity: number, ms: number, now: number): void {
  store.shake = {
    intensity: Math.max(store.shake.intensity, intensity),
    until: Math.max(store.shake.until, now + ms),
  };
}

function addFlash(
  store: HitEffectStore,
  color: string,
  alpha: number,
  ms: number,
  now: number,
): void {
  store.flash = { color, alpha, until: now + ms };
}

function maybeShockwave(
  store: HitEffectStore,
  ctx: HitEffectContext,
): void {
  const floorY = ctx.arenaHeight * 0.82;
  if (ctx.contactY < floorY || ctx.damage < MEDIUM_DAMAGE) return;

  const wave: GroundShockwave = {
    x: ctx.contactX,
    y: ctx.contactY,
    born: ctx.now,
    color: ctx.aggressorColor,
    power: Math.min(1, ctx.damage / 70),
  };
  store.shockwaves.push(wave);
  if (store.shockwaves.length > 6) {
    store.shockwaves.splice(0, store.shockwaves.length - 6);
  }
}

/** Триггер MK-эффектов при ударе (#3 #4 #5 #10 #17 #18 #19). */
export function dispatchHitEffects(
  store: HitEffectStore,
  ctx: HitEffectContext,
): void {
  const { damage, now } = ctx;
  if (damage <= 0.5) return;

  const power = Math.min(1, damage / 80);

  // #4 Screen shake — от средних ударов
  if (damage >= MEDIUM_DAMAGE) {
    addShake(store, 4 + power * 10, 180 + power * 120, now);
  } else {
    addShake(store, 2 + power * 4, 90, now);
  }

  // #5 Flash frame
  const flashAlpha =
    damage >= HEAVY_DAMAGE ? 0.42 : damage >= MEDIUM_DAMAGE ? 0.22 : 0.12;
  addFlash(store, ctx.aggressorColor, flashAlpha, damage >= HEAVY_DAMAGE ? 90 : 55, now);

  // Impact frames (ч/б-негатив) на тяжёлых — без punch-zoom камеры (дёргает lookAt).
  if (damage >= HEAVY_DAMAGE) {
    store.impactInvertUntil = Math.max(
      store.impactInvertUntil,
      now + IMPACT_FRAME_MS,
    );
    scheduleTimeFx(store, 0, now, HIT_STOP_MS);
    scheduleTimeFx(store, SLOW_MO_SCALE, now + HIT_STOP_MS, SLOW_MO_MS);
  } else if (damage >= MEDIUM_DAMAGE * 1.4) {
    scheduleTimeFx(store, 0.55, now, 140);
  }

  maybeShockwave(store, ctx);

  const combo = updateCombo(store, ctx.aggressorSide, now);
  if (combo >= 3 && combo <= 4) {
    playComboSound();
  } else if (combo >= 5) {
    playComboSound();
  }

  // Crowd meter lite: на ×5 сыплем искры
  if (combo > 0 && combo % 5 === 0) {
    store.comboSparks.push({
      x: ctx.contactX,
      y: ctx.contactY,
      born: now,
      color: ctx.aggressorColors.main,
      secondary: ctx.aggressorColors.secondary,
      power: Math.min(1, 0.55 + combo * 0.06),
    });
    if (store.comboSparks.length > 8) {
      store.comboSparks.splice(0, store.comboSparks.length - 8);
    }
    addFlash(store, "#fff7ed", 0.2, 70, now);
    addShake(store, 5, 160, now);
  }

  if (store.combo && now - store.combo.lastHitAt > COMBO_WINDOW_MS) {
    store.combo = null;
  }
}

/** Finisher-камера + вспышка при нокауте (#12). */
export function dispatchKnockoutEffects(
  store: HitEffectStore,
  _winner: FighterSide,
  focusX: number,
  focusY: number,
  _language: Language,
  _slot: number,
  now: number,
  _winnerColors: FighterColors,
): void {
  store.finisher = {
    active: true,
    until: now + FINISHER_MS,
    focusX,
    focusY,
    zoom: 0.48,
  };
  store.impactInvertUntil = Math.max(store.impactInvertUntil, now + 110);
  scheduleTimeFx(store, 0, now, 140);
  scheduleTimeFx(store, 0.28, now + 140, 520);
  addShake(store, 14, 700, now);
  addFlash(store, "#ffffff", 0.55, 120, now);
  store.comboSparks.push({
    x: focusX,
    y: focusY,
    born: now,
    color: _winnerColors.main,
    secondary: _winnerColors.secondary,
    power: 1,
  });
}

/** Лёгкий juice при разлёте частей на KO. */
export function dispatchVictoryScatterEffects(
  store: HitEffectStore,
  _x: number,
  _y: number,
  color: string,
  now: number,
): void {
  addShake(store, 6, 220, now);
  addFlash(store, color, 0.28, 80, now);
}

export { comboLabel };
