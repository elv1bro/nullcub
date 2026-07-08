/**
 * WebAudio-движок сэмплов: декодирует OGG в AudioBuffer при первом
 * обращении (дальше из кэша), играет со случайным питчем и стерео-панорамой.
 * Против new Audio(url): нет задержки на повторную загрузку, нет мусора из
 * HTMLAudioElement, есть pitch/pan.
 */

import { audioContext, isSoundEffectsEnabled, sfxMaster } from "./context";

const bufferCache = new Map<string, AudioBuffer | "loading" | "failed">();

function loadBuffer(url: string): void {
  const context = audioContext();
  if (!context || bufferCache.has(url)) return;
  bufferCache.set(url, "loading");
  fetch(url)
    .then((res) => {
      if (!res.ok) throw new Error(String(res.status));
      return res.arrayBuffer();
    })
    .then((raw) => context.decodeAudioData(raw))
    .then((decoded) => {
      bufferCache.set(url, decoded);
    })
    .catch(() => {
      bufferCache.set(url, "failed");
    });
}

/** Прогреть кэш (например, все сэмплы ударов при старте боя). */
export function preloadSamples(urls: readonly string[]): void {
  for (const url of urls) loadBuffer(url);
}

export interface SamplePlayOptions {
  volume: number;
  /** Разброс питча в полутонах (±). */
  pitchSpreadSemitones?: number;
  /** Стерео-позиция -1..1 (лево..право). */
  pan?: number;
}

/**
 * Играет сэмпл, если буфер уже декодирован. Если ещё грузится — ставит
 * загрузку и возвращает false (вызывающий может сыграть процедурный звук).
 */
export function playSampleBuffer(
  url: string,
  { volume, pitchSpreadSemitones = 0, pan = 0 }: SamplePlayOptions,
): boolean {
  if (!isSoundEffectsEnabled()) return false;
  const context = audioContext();
  const out = sfxMaster();
  if (!context || !out) return false;

  const cached = bufferCache.get(url);
  if (cached === undefined) {
    loadBuffer(url);
    return false;
  }
  if (cached === "loading") return false;
  if (cached === "failed") return false;

  const source = context.createBufferSource();
  source.buffer = cached;
  if (pitchSpreadSemitones > 0) {
    const semitones = (Math.random() * 2 - 1) * pitchSpreadSemitones;
    source.playbackRate.value = Math.pow(2, semitones / 12);
  }

  const gain = context.createGain();
  gain.gain.value = Math.max(0.02, Math.min(1, volume));

  let head: AudioNode = source;
  if (pan !== 0 && typeof context.createStereoPanner === "function") {
    const panner = context.createStereoPanner();
    panner.pan.value = Math.max(-1, Math.min(1, pan));
    source.connect(panner);
    head = panner;
  }

  head.connect(gain);
  gain.connect(out);
  source.start();
  return true;
}
