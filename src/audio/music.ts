/**
 * Музыка: луп меню, боевой плейлист в духе FlatOut 2 (перемешка, кроссфейд,
 * трек-анонсы), дакинг под тяжёлые удары, пауза при скрытой вкладке.
 *
 * Треки — CC0 с OpenGameArt (источники в public/sounds/music/README.txt).
 * Джинглы победы/поражения — в src/audio/sfx.ts (public/sounds/sfx/).
 */

import { isTestEnv } from "./isTestEnv";

export interface MusicTrack {
  url: string;
  title: string;
  artist: string;
}

const MUSIC = "/sounds/music";

export const MENU_TRACK: MusicTrack = {
  url: `${MUSIC}/menu-theme.ogg`,
  title: "Cozy Puzzle Title",
  artist: "MintoDog",
};

export const BATTLE_PLAYLIST: readonly MusicTrack[] = [
  { url: `${MUSIC}/battle-01.ogg`, title: "Epic Rock Battle", artist: "HydroGene" },
  { url: `${MUSIC}/battle-02.ogg`, title: "Ente Evil", artist: "The Real Monoton Artist" },
  { url: `${MUSIC}/battle-03.ogg`, title: "Trance Boss Battle", artist: "MintoDog" },
  { url: `${MUSIC}/battle-04.ogg`, title: "Battle Theme A", artist: "cynicmusic" },
];

/** Дефолт 30% — чтобы музыка не заглушала реплики и удары. */
export const DEFAULT_MUSIC_VOLUME = 0.3;

type MusicMode = "off" | "menu" | "battle";

const TRACK_CROSSFADE_MS = 2400;
const SKIP_CROSSFADE_MS = 900;
const DUCK_RECOVER_MS = 700;
const MIXER_TICK_MS = 60;

/** Пара каналов для кроссфейда: пока один затухает, второй набирает. */
interface Channel {
  el: HTMLAudioElement;
  fade: number;
  fadeTarget: number;
  fadeMs: number;
}

let channels: [Channel, Channel] | null = null;
let activeIdx = 0;
let mode: MusicMode = "off";
let queue: MusicTrack[] = [];
let queueIdx = 0;
let current: MusicTrack | null = null;
let volume = isTestEnv() ? 0 : DEFAULT_MUSIC_VOLUME;
let enabled = !isTestEnv();
let duck = 1;
let duckHoldUntil = 0;
let mixerTimer: number | null = null;
let lastTick = 0;
let crossfadeArmed = false;
let unlockArmed = false;

type NowPlayingListener = (track: MusicTrack | null) => void;
const listeners = new Set<NowPlayingListener>();

function notify(): void {
  for (const fn of listeners) fn(current);
}

/** Подписка на смену трека (для виджета «сейчас играет»). */
export function subscribeNowPlaying(fn: NowPlayingListener): () => void {
  listeners.add(fn);
  fn(current);
  return () => {
    listeners.delete(fn);
  };
}

export function getNowPlaying(): MusicTrack | null {
  return current;
}

function clamp01(v: number): number {
  return Math.max(0, Math.min(1, v));
}

function applyChannelVolume(ch: Channel): void {
  ch.el.volume = clamp01(volume * duck * ch.fade);
}

/**
 * Автоплей до первого жеста пользователя запрещён браузером — вешаем
 * одноразовый ретрай на pointerdown/keydown.
 */
function armUnlock(): void {
  if (unlockArmed || typeof window === "undefined") return;
  unlockArmed = true;
  const resume = () => {
    unlockArmed = false;
    window.removeEventListener("pointerdown", resume);
    window.removeEventListener("keydown", resume);
    if (channels && mode !== "off" && enabled) {
      void channels[activeIdx]!.el.play().catch(() => armUnlock());
    }
  };
  window.addEventListener("pointerdown", resume);
  window.addEventListener("keydown", resume);
}

function onVisibilityChange(): void {
  if (document.hidden) stopMusic(200);
}

function onPageHide(): void {
  stopMusic(0);
}

function makeChannel(): Channel {
  const el = new Audio();
  el.preload = "auto";
  const ch: Channel = { el, fade: 0, fadeTarget: 0, fadeMs: 300 };

  el.addEventListener("timeupdate", () => {
    if (!channels || mode !== "battle" || crossfadeArmed) return;
    if (channels[activeIdx] !== ch || el.loop) return;
    if (!Number.isFinite(el.duration) || el.duration <= 0) return;
    if ((el.duration - el.currentTime) * 1000 <= TRACK_CROSSFADE_MS) {
      crossfadeArmed = true;
      nextInQueue(TRACK_CROSSFADE_MS);
    }
  });

  // Страховка: если timeupdate не успел (вкладка троттлится) — жёсткий стык.
  el.addEventListener("ended", () => {
    if (!channels || mode !== "battle") return;
    if (channels[activeIdx] !== ch) return;
    nextInQueue(0);
  });

  return ch;
}

function ensureChannels(): [Channel, Channel] {
  if (!channels) {
    channels = [makeChannel(), makeChannel()];
    if (typeof document !== "undefined") {
      document.addEventListener("visibilitychange", onVisibilityChange);
      window.addEventListener("pagehide", onPageHide);
      window.addEventListener("beforeunload", onPageHide);
    }
  }
  return channels;
}

/** Снимает page-lifecycle listeners и останавливает микшер (для unmount / HMR). */
export function disposeMusic(): void {
  stopMusic(0);
  if (mixerTimer !== null && typeof window !== "undefined") {
    window.clearInterval(mixerTimer);
    mixerTimer = null;
  }
  if (typeof document !== "undefined") {
    document.removeEventListener("visibilitychange", onVisibilityChange);
    window.removeEventListener("pagehide", onPageHide);
    window.removeEventListener("beforeunload", onPageHide);
  }
  if (channels) {
    for (const ch of channels) {
      ch.el.pause();
      ch.el.removeAttribute("src");
      ch.el.load();
    }
    channels = null;
  }
}

function hasAudible(): boolean {
  return !!channels && !channels[activeIdx]!.el.paused;
}

function mixerActive(): boolean {
  if (duck < 1 || performance.now() < duckHoldUntil) return true;
  if (!channels) return false;
  return channels.some((c) => c.fade !== c.fadeTarget);
}

function startMixer(): void {
  if (mixerTimer !== null || typeof window === "undefined") return;
  lastTick = performance.now();
  mixerTimer = window.setInterval(() => {
    const now = performance.now();
    const dt = now - lastTick;
    lastTick = now;

    if (now >= duckHoldUntil && duck < 1) {
      duck = Math.min(1, duck + dt / DUCK_RECOVER_MS);
    }

    if (channels) {
      for (const ch of channels) {
        if (ch.fade !== ch.fadeTarget) {
          const step = dt / Math.max(1, ch.fadeMs);
          ch.fade =
            ch.fade < ch.fadeTarget
              ? Math.min(ch.fadeTarget, ch.fade + step)
              : Math.max(ch.fadeTarget, ch.fade - step);
          if (ch.fade <= 0 && ch.fadeTarget <= 0 && !ch.el.paused) {
            ch.el.pause();
          }
        }
        applyChannelVolume(ch);
      }
    }

    if (!mixerActive() && mixerTimer !== null) {
      window.clearInterval(mixerTimer);
      mixerTimer = null;
    }
  }, MIXER_TICK_MS);
}

function startTrack(track: MusicTrack, loop: boolean, fadeMs: number): void {
  const chs = ensureChannels();
  crossfadeArmed = false;

  const fadeIn = fadeMs > 0;
  if (fadeIn && hasAudible()) {
    const old = chs[activeIdx]!;
    old.fadeTarget = 0;
    old.fadeMs = fadeMs;
    activeIdx = 1 - activeIdx;
  } else {
    const other = chs[1 - activeIdx]!;
    other.fade = 0;
    other.fadeTarget = 0;
    other.el.pause();
  }

  const ch = chs[activeIdx]!;
  ch.el.loop = loop;
  ch.el.src = track.url;
  ch.fade = fadeIn ? 0 : 1;
  ch.fadeTarget = 1;
  ch.fadeMs = fadeIn ? fadeMs : 200;
  applyChannelVolume(ch);

  current = track;
  notify();

  if (!enabled) {
    ch.el.pause();
    return;
  }
  void ch.el.play().catch(() => armUnlock());
  startMixer();
}

function shuffled<T>(arr: readonly T[]): T[] {
  const out = [...arr];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

function nextInQueue(fadeMs: number): void {
  if (queue.length === 0) return;
  queueIdx = (queueIdx + 1) % queue.length;
  startTrack(queue[queueIdx]!, false, fadeMs);
}

function prevInQueue(fadeMs: number): void {
  if (queue.length === 0) return;
  queueIdx = (queueIdx - 1 + queue.length) % queue.length;
  startTrack(queue[queueIdx]!, false, fadeMs);
}

/** Зацикленная тема меню. Повторный вызов ничего не перезапускает. */
export function playMenuMusic(): void {
  if (mode === "menu") return;
  mode = "menu";
  queue = [];
  startTrack(MENU_TRACK, true, hasAudible() ? TRACK_CROSSFADE_MS : 1200);
}

/** Боевой плейлист: перемешивается, треки сменяются кроссфейдом. */
export function playBattleMusic(): void {
  if (mode === "battle") return;
  mode = "battle";
  queue = shuffled(BATTLE_PLAYLIST);
  queueIdx = 0;
  startTrack(queue[0]!, false, hasAudible() ? TRACK_CROSSFADE_MS : 500);
}

/** Следующий трек боевого плейлиста (кнопка «skip»). */
export function skipBattleTrack(): void {
  if (mode === "battle") nextInQueue(SKIP_CROSSFADE_MS);
}

/** Предыдущий трек боевого плейлиста. */
export function prevBattleTrack(): void {
  if (mode === "battle") prevInQueue(SKIP_CROSSFADE_MS);
}

export function stopMusic(fadeMs = 0): void {
  mode = "off";
  current = null;
  duck = 1;
  duckHoldUntil = 0;
  notify();
  if (!channels) return;
  for (const ch of channels) {
    if (fadeMs <= 0) {
      ch.fade = 0;
      ch.fadeTarget = 0;
      ch.el.pause();
      applyChannelVolume(ch);
    } else if (!ch.el.paused) {
      ch.fadeTarget = 0;
      ch.fadeMs = fadeMs;
    }
  }
  if (fadeMs > 0) startMixer();
}

/**
 * Дакинг: музыка мгновенно приседает до factor и после holdMs плавно
 * возвращается. Вызывается из sfx на тяжёлых ударах и нокауте.
 */
export function duckMusic(factor: number, holdMs: number): void {
  if (mode === "off" || !enabled) return;
  duck = Math.min(duck, clamp01(factor));
  duckHoldUntil = Math.max(duckHoldUntil, performance.now() + holdMs);
  startMixer();
}

export function setMusicVolume(v: number): void {
  volume = clamp01(v);
  if (channels) {
    for (const ch of channels) applyChannelVolume(ch);
  }
}

export function getMusicVolume(): number {
  return volume;
}

export function setMusicEnabled(on: boolean): void {
  enabled = on;
  if (!channels || mode === "off") return;
  if (!on) {
    for (const ch of channels) ch.el.pause();
    return;
  }
  const ch = channels[activeIdx]!;
  ch.fadeTarget = 1;
  applyChannelVolume(ch);
  void ch.el.play().catch(() => armUnlock());
  startMixer();
}

export function isMusicEnabled(): boolean {
  return enabled;
}
