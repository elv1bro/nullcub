import { isTestEnv } from "./isTestEnv";
import {
  setSfxVolume,
  setSoundEffectsEnabled,
} from "./context";
import { setMusicEnabled, setMusicVolume } from "./music";

/** Нулевая громкость и выключенный звук для vitest. */
export function applyTestSilence(): void {
  if (!isTestEnv()) return;
  setSfxVolume(0);
  setSoundEffectsEnabled(false);
  setMusicVolume(0);
  setMusicEnabled(false);
}
