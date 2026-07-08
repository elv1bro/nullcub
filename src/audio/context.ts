/** Общий AudioContext, тумблер звуковых эффектов и их громкость. */

import { isTestEnv } from "./isTestEnv";

const BASE_SFX_GAIN = 0.82;

export const DEFAULT_SFX_VOLUME = 1;

let audioCtx: AudioContext | null = null;
let masterGain: GainNode | null = null;
let soundEnabled = !isTestEnv();
let sfxVolume = isTestEnv() ? 0 : DEFAULT_SFX_VOLUME;

export function audioContext(): AudioContext | null {
  if (typeof window === "undefined" || isTestEnv()) return null;
  if (!audioCtx) {
    try {
      audioCtx = new AudioContext();
    } catch {
      return null;
    }
  }
  if (audioCtx.state === "suspended") {
    void audioCtx.resume();
  }
  return audioCtx;
}

/** Общий выход всех звуковых эффектов (процедурных и сэмплов). */
export function sfxMaster(): GainNode | null {
  const context = audioContext();
  if (!context) return null;
  if (!masterGain) {
    masterGain = context.createGain();
    masterGain.gain.value = BASE_SFX_GAIN * sfxVolume;
    masterGain.connect(context.destination);
  }
  return masterGain;
}

export function setSoundEffectsEnabled(on: boolean): void {
  soundEnabled = on;
}

export function isSoundEffectsEnabled(): boolean {
  return soundEnabled;
}

export function setSfxVolume(v: number): void {
  sfxVolume = Math.max(0, Math.min(1, v));
  if (masterGain) masterGain.gain.value = BASE_SFX_GAIN * sfxVolume;
}

export function getSfxVolume(): number {
  return sfxVolume;
}
