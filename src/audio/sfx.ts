/**
 * Звуки боя и UI-меню: CC0 сэмплы через WebAudio (предзагрузка, случайный
 * питч, стерео-панорама) + процедурный fallback, пока буфер не декодирован.
 */

import { HEAVY_DAMAGE, MEDIUM_DAMAGE } from "@/lib/hitEffects/store";
import { audioContext, isSoundEffectsEnabled, sfxMaster } from "./context";
import { duckMusic } from "./music";
import { playSampleBuffer, preloadSamples } from "./sampleEngine";

export type MenuSound = "hover" | "click" | "panel" | "play";

type SfxKind =
  | "hitLight"
  | "hitMedium"
  | "hitHeavy"
  | "ko"
  | "combo"
  | "chainRattle"
  | "chainBreak";

const COMBAT = "/sounds/combat";
const ATMOSPHERE = "/sounds/sfx";

/** Атмосфера боя: гонг, толпа, джинглы результата (CC0, см. public/sounds/sfx/README.txt). */
const ATMOSPHERE_SAMPLES = {
  gong: `${ATMOSPHERE}/fight-gong.ogg`,
  crowdCheer: `${ATMOSPHERE}/crowd-cheer.ogg`,
  crowdOof: `${ATMOSPHERE}/crowd-oof.ogg`,
  victory: `${ATMOSPHERE}/victory.ogg`,
  defeat: `${ATMOSPHERE}/defeat.ogg`,
} as const;

function hits(from: number, to: number): string[] {
  const out: string[] = [];
  for (let i = from; i <= to; i++) {
    out.push(`${COMBAT}/hits/hit-${String(i).padStart(2, "0")}.ogg`);
  }
  return out;
}

const SAMPLE_URLS: Record<SfxKind, readonly string[]> = {
  // Independent.nu — короткие шлепки/тычки
  hitLight: hits(1, 14),
  // Средние удары + qubodup (мясистые)
  hitMedium: [
    ...hits(15, 26),
    `${COMBAT}/qubodup/qubodupPunch01.ogg`,
    `${COMBAT}/qubodup/qubodupPunch02.ogg`,
    `${COMBAT}/qubodup/qubodupPunch03.ogg`,
  ],
  // Тяжёлые удары
  hitHeavy: [
    ...hits(27, 37),
    `${COMBAT}/qubodup/qubodupPunch04.ogg`,
    `${COMBAT}/qubodup/qubodupPunch05.ogg`,
  ],
  ko: [`${COMBAT}/ko-01.ogg`, `${COMBAT}/ko-02.ogg`],
  combo: [
    `${COMBAT}/zap_1.ogg`,
    `${COMBAT}/zap_2.ogg`,
    `${COMBAT}/phaser_up_1.ogg`,
    `${COMBAT}/phaser_up_3.ogg`,
  ],
  chainRattle: hits(8, 12),
  chainBreak: [
    `${COMBAT}/qubodup/qubodupPunch05.ogg`,
    `${COMBAT}/hits/hit-35.ogg`,
    `${COMBAT}/hits/hit-36.ogg`,
  ],
};

const SAMPLE_GAIN: Record<SfxKind, number> = {
  hitLight: 0.72,
  hitMedium: 0.82,
  hitHeavy: 0.92,
  ko: 0.95,
  combo: 0.45,
  chainRattle: 0.42,
  chainBreak: 0.88,
};

/** Разброс питча в полутонах — чтобы сэмплы не звучали одинаково. */
const PITCH_SPREAD: Record<SfxKind, number> = {
  hitLight: 2.5,
  hitMedium: 2,
  hitHeavy: 1.5,
  ko: 0.8,
  combo: 0.5,
  chainRattle: 3,
  chainBreak: 1.5,
};

/** Прогрев кэша сэмплов боя — вызывается при входе в бой. */
export function preloadCombatAudio(): void {
  preloadSamples([
    ...Object.values(SAMPLE_URLS).flat(),
    ...Object.values(ATMOSPHERE_SAMPLES),
  ]);
}

/** Стерео-позиция по X в координатах арены, слегка сглаженная к центру. */
export function stereoPanForX(x: number, minX: number, maxX: number): number {
  if (!(maxX > minX)) return 0;
  const norm = ((x - minX) / (maxX - minX)) * 2 - 1;
  return Math.max(-1, Math.min(1, norm)) * 0.7;
}

function pickSample(kind: SfxKind): string {
  const pool = SAMPLE_URLS[kind];
  return pool[Math.floor(Math.random() * pool.length)]!;
}

function tone(
  frequency: number,
  duration: number,
  type: OscillatorType,
  gain: number,
  decay = duration,
  detune = 0,
): void {
  const context = audioContext();
  const out = sfxMaster();
  if (!context || !out || !isSoundEffectsEnabled()) return;

  const osc = context.createOscillator();
  const g = context.createGain();
  osc.type = type;
  osc.frequency.value = frequency;
  osc.detune.value = detune;
  g.gain.setValueAtTime(gain, context.currentTime);
  g.gain.exponentialRampToValueAtTime(0.001, context.currentTime + decay);
  osc.connect(g);
  g.connect(out);
  osc.start();
  osc.stop(context.currentTime + duration + 0.02);
}

function noiseBurst(
  duration: number,
  gain: number,
  filterHz?: number,
  filterType: BiquadFilterType = "bandpass",
): void {
  const context = audioContext();
  const out = sfxMaster();
  if (!context || !out || !isSoundEffectsEnabled()) return;

  const samples = Math.max(1, Math.floor(context.sampleRate * duration));
  const buffer = context.createBuffer(1, samples, context.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < samples; i++) {
    data[i] = Math.random() * 2 - 1;
  }

  const source = context.createBufferSource();
  source.buffer = buffer;
  const g = context.createGain();
  g.gain.setValueAtTime(gain, context.currentTime);
  g.gain.exponentialRampToValueAtTime(0.001, context.currentTime + duration);

  let node: AudioNode = source;
  if (filterHz) {
    const filter = context.createBiquadFilter();
    filter.type = filterType;
    filter.frequency.value = filterHz;
    filter.Q.value = 1.4;
    source.connect(filter);
    node = filter;
  }

  node.connect(g);
  g.connect(out);
  source.start();
  source.stop(context.currentTime + duration + 0.01);
}

function playAtmosphere(
  url: string,
  volume: number,
  pitchSpreadSemitones = 0,
): boolean {
  return playSampleBuffer(url, { volume, pitchSpreadSemitones });
}

function playCrowdReaction(kind: "cheer" | "oof"): void {
  if (!isSoundEffectsEnabled()) return;
  if (kind === "cheer") {
    if (playAtmosphere(ATMOSPHERE_SAMPLES.crowdCheer, 0.62)) return;
    // fallback: короткий шумовой swell
    noiseBurst(0.5, 0.06, 900, "bandpass");
  } else {
    if (playAtmosphere(ATMOSPHERE_SAMPLES.crowdOof, 0.45, 0.3)) return;
    noiseBurst(0.25, 0.04, 700, "bandpass");
  }
}

function playSfxProcedural(kind: SfxKind, intensity = 1): void {
  if (!isSoundEffectsEnabled()) return;
  const k = Math.max(0.35, Math.min(1.4, intensity));

  switch (kind) {
    case "hitLight":
      noiseBurst(0.04, 0.045 * k, 900, "highpass");
      tone(140, 0.07, "triangle", 0.05 * k, 0.08);
      break;
    case "hitMedium":
      noiseBurst(0.06, 0.07 * k, 650);
      tone(95, 0.09, "square", 0.035 * k, 0.1);
      tone(210, 0.05, "sine", 0.025 * k, 0.06);
      break;
    case "hitHeavy":
      noiseBurst(0.1, 0.11 * k, 420);
      tone(62, 0.14, "triangle", 0.08 * k, 0.16);
      tone(124, 0.08, "sine", 0.04 * k, 0.1);
      break;
    case "ko":
      tone(180, 0.2, "sawtooth", 0.06, 0.22);
      tone(120, 0.25, "triangle", 0.07, 0.28);
      tone(70, 0.35, "sine", 0.08, 0.38);
      noiseBurst(0.14, 0.09, 300, "lowpass");
      break;
    case "combo":
      tone(440, 0.06, "square", 0.03, 0.07);
      tone(660, 0.07, "square", 0.028, 0.08);
      tone(880, 0.09, "sine", 0.025, 0.1);
      break;
    case "chainRattle":
      noiseBurst(0.05, 0.035 * k, 2400, "bandpass");
      tone(780 + Math.random() * 120, 0.03, "triangle", 0.018 * k, 0.04);
      break;
    case "chainBreak":
      noiseBurst(0.07, 0.06, 1800, "highpass");
      tone(920, 0.04, "square", 0.035, 0.05);
      tone(640, 0.05, "triangle", 0.03, 0.06);
      tone(320, 0.08, "sine", 0.04, 0.1);
      tone(180, 0.12, "sine", 0.05, 0.14);
      break;
  }
}

function playSfx(kind: SfxKind, intensity = 1, pan = 0): void {
  if (!isSoundEffectsEnabled()) return;
  const vol = SAMPLE_GAIN[kind] * Math.max(0.5, Math.min(1.2, intensity));
  const played = playSampleBuffer(pickSample(kind), {
    volume: vol,
    pitchSpreadSemitones: PITCH_SPREAD[kind],
    pan,
  });
  if (!played) playSfxProcedural(kind, intensity);
}

export function playMenuSound(kind: MenuSound): void {
  if (!isSoundEffectsEnabled()) return;
  switch (kind) {
    case "hover":
      tone(520, 0.04, "sine", 0.025, 0.04);
      break;
    case "click":
      tone(380, 0.06, "triangle", 0.04, 0.07);
      break;
    case "panel":
      tone(280, 0.08, "sine", 0.035, 0.1);
      tone(420, 0.06, "sine", 0.02, 0.08);
      break;
    case "play":
      tone(220, 0.12, "triangle", 0.05, 0.15);
      tone(330, 0.1, "sine", 0.035, 0.12);
      tone(440, 0.08, "sine", 0.025, 0.1);
      break;
  }
}

export function playHitSound(damage: number, pan = 0): void {
  if (damage <= 0.5) return;
  if (damage >= HEAVY_DAMAGE) {
    playSfx("hitHeavy", damage / HEAVY_DAMAGE, pan);
    duckMusic(0.55, 220);
    if (Math.random() < 0.3) playCrowdReaction("oof");
  } else if (damage >= MEDIUM_DAMAGE) {
    playSfx("hitMedium", damage / MEDIUM_DAMAGE, pan);
  } else {
    playSfx("hitLight", Math.min(1, damage / MEDIUM_DAMAGE), pan);
  }
}

export function playKnockoutSound(): void {
  playSfx("ko");
  duckMusic(0.22, 800);
  playCrowdReaction("cheer");
}

export function playComboSound(): void {
  playSfx("combo");
}

export function playChainRattleSound(intensity = 1): void {
  playSfx("chainRattle", intensity);
}

export function playChainBreakSound(): void {
  playSfx("chainBreak");
}

/** Гонг старта боя — боксёрский колокол (CC0), процедурный fallback. */
export function playGongSound(): void {
  if (!isSoundEffectsEnabled()) return;
  if (playAtmosphere(ATMOSPHERE_SAMPLES.gong, 0.7)) return;
  tone(220, 1.6, "sine", 0.07, 1.8);
  tone(329, 1.2, "sine", 0.05, 1.4, 8);
  tone(554, 0.9, "sine", 0.035, 1.1, -6);
  tone(110, 2.0, "triangle", 0.05, 2.2);
  noiseBurst(0.05, 0.05, 3000, "highpass");
}

/**
 * Джингл победы/поражения. Отдельный от музыки звук — подчиняется тумблеру
 * звуковых эффектов, а не музыки.
 */
export function playResultSting(kind: "victory" | "defeat"): void {
  if (!isSoundEffectsEnabled()) return;
  const url =
    kind === "victory"
      ? ATMOSPHERE_SAMPLES.victory
      : ATMOSPHERE_SAMPLES.defeat;
  if (playAtmosphere(url, 0.58)) return;
  // fallback: короткое арпеджио
  if (kind === "victory") {
    tone(523, 0.2, "sine", 0.05, 0.22);
    tone(659, 0.2, "sine", 0.045, 0.22);
    tone(784, 0.25, "sine", 0.04, 0.28);
  } else {
    tone(392, 0.25, "sine", 0.05, 0.28);
    tone(349, 0.3, "sine", 0.045, 0.32);
    tone(311, 0.35, "sine", 0.04, 0.38);
  }
}

// --- Heartbeat при низком HP ---

let heartbeatTimer: number | null = null;
let heartbeatLevel = 0;

function scheduleHeartbeat(): void {
  const interval = 1150 - 550 * heartbeatLevel;
  heartbeatTimer = window.setTimeout(() => {
    if (heartbeatLevel <= 0) {
      heartbeatTimer = null;
      return;
    }
    if (isSoundEffectsEnabled()) {
      const g = 0.05 + 0.05 * heartbeatLevel;
      tone(56, 0.11, "sine", g, 0.13);
      window.setTimeout(() => {
        if (heartbeatLevel > 0 && isSoundEffectsEnabled()) {
          tone(48, 0.1, "sine", g * 0.75, 0.12);
        }
      }, 150);
    }
    scheduleHeartbeat();
  }, interval);
}

/**
 * Интенсивность сердцебиения 0..1 (0 — выключить). Дергается из боя
 * при изменении HP; сам звук — тихие низкие «туки», учащаются к нулю HP.
 */
export function setHeartbeatLevel(level: number): void {
  const next = Math.max(0, Math.min(1, level));
  const wasOff = heartbeatLevel <= 0;
  heartbeatLevel = next;
  if (next <= 0) {
    if (heartbeatTimer !== null) {
      clearTimeout(heartbeatTimer);
      heartbeatTimer = null;
    }
    return;
  }
  if (wasOff && heartbeatTimer === null && typeof window !== "undefined") {
    scheduleHeartbeat();
  }
}
