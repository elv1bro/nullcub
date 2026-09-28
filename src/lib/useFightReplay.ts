import { useEngine, useEventBeforeUpdate } from "@1.framework/matter4react";
import type { Body } from "matter-js";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type RefObject,
} from "react";
import {
  FightTape,
  FIGHT_TAPE_HZ,
  REPLAY_HIT_HOLD_MS,
  applyFightTapePoses,
  peakExcitementAhead,
  speedFromExcitement,
  type FightTapeHitEvent,
} from "./fightTape";

export const REPLAY_SPEEDS = [1, 2, 4, 8] as const;
export type ReplaySpeed = (typeof REPLAY_SPEEDS)[number];
/** Auto = скорость от волны урона; иначе ручной множитель. */
export type ReplaySpeedMode = "auto" | ReplaySpeed;

interface Opts {
  enabled: boolean;
  tapeRef: RefObject<FightTape>;
  getBodies: () => Body[];
  /** Спавн брызг / фраз / hit-FX при проходе события на ленте. */
  onReplayEvent?: (event: FightTapeHitEvent) => void;
  /** Очистить визуальные FX при seek назад / старте. */
  onClearReplayFx?: () => void;
  /** Дошли до конца повтора (KO + хвост) — обычно «к итогам». */
  onEnded?: () => void;
  initialMode?: ReplaySpeedMode;
  /** Если задан — стоп на конце выделенного клипа (без авто-recap). */
  clipEndMsRef?: RefObject<number | null>;
}

/**
 * Кинематический повтор: двигает тела по ленте, физику глушит через timeScale=0.
 * React-стейт для HUD обновляется реже (~12 Гц), чтобы не жечь ререндеры.
 */
export function useFightReplay(opts: Opts) {
  const engine = useEngine();
  const [playing, setPlaying] = useState(true);
  const [speedMode, setSpeedMode] = useState<ReplaySpeedMode>(
    opts.initialMode ?? "auto",
  );
  const [effectiveSpeed, setEffectiveSpeed] = useState(2);
  const [wave, setWave] = useState<number[]>([]);
  const [ui, setUi] = useState({
    playheadRatio: 0,
    playheadMs: 0,
    frameIndex: 0,
    durationMs: 0,
    frameCount: 0,
  });

  const playheadMsRef = useRef(0);
  const lastTickRef = useRef(0);
  const lastUiRef = useRef(0);
  const smoothSpeedRef = useRef(1.6);
  const slowHoldUntilRef = useRef(0);
  const poseScratchRef = useRef<Float32Array | null>(null);
  const playingRef = useRef(playing);
  const speedModeRef = useRef(speedMode);
  const onReplayEventRef = useRef(opts.onReplayEvent);
  const onClearReplayFxRef = useRef(opts.onClearReplayFx);
  const onEndedRef = useRef(opts.onEnded);
  const endedFiredRef = useRef(false);
  playingRef.current = playing;
  speedModeRef.current = speedMode;
  onReplayEventRef.current = opts.onReplayEvent;
  onClearReplayFxRef.current = opts.onClearReplayFx;
  onEndedRef.current = opts.onEnded;

  useEffect(() => {
    if (!opts.enabled) {
      engine.timing.timeScale = 1;
      setPlaying(true);
      playheadMsRef.current = 0;
      smoothSpeedRef.current = 1.6;
      slowHoldUntilRef.current = 0;
      setWave([]);
      setEffectiveSpeed(1.6);
      setUi({
        playheadRatio: 0,
        playheadMs: 0,
        frameIndex: 0,
        durationMs: 0,
        frameCount: 0,
      });
      return undefined;
    }
    const tape = opts.tapeRef.current;
    tape?.freeze();
    playheadMsRef.current = 0;
    lastTickRef.current = performance.now();
    lastUiRef.current = 0;
    smoothSpeedRef.current = 1.6;
    slowHoldUntilRef.current = 0;
    endedFiredRef.current = false;
    setPlaying(true);
    setSpeedMode(opts.initialMode ?? "auto");
    const endMs = tape?.playbackEndMs ?? 0;
    setWave(tape?.waveSamples(72, endMs) ?? []);
    setUi({
      playheadRatio: 0,
      playheadMs: 0,
      frameIndex: 0,
      durationMs: endMs,
      frameCount: tape?.frameCount ?? 0,
    });
    onClearReplayFxRef.current?.();
    engine.timing.timeScale = 0;
    return () => {
      engine.timing.timeScale = 1;
    };
  }, [opts.enabled, opts.tapeRef, engine, opts.initialMode]);

  useEventBeforeUpdate(() => {
    if (!opts.enabled) return;
    // Держим физику замороженной даже если hit-clock/другое трогает timeScale.
    engine.timing.timeScale = 0;
    const tape = opts.tapeRef.current;
    if (!tape || tape.frameCount === 0) return;

    const now = performance.now();
    const dt = Math.min(100, now - lastTickRef.current);
    lastTickRef.current = now;

    const mode = speedModeRef.current;
    let speed: number;
    const tapeEnd = tape.playbackEndMs;
    const clipEnd = opts.clipEndMsRef?.current;
    const endMs =
      clipEnd != null && Number.isFinite(clipEnd)
        ? Math.min(tapeEnd, Math.max(0, clipEnd))
        : tapeEnd;
    const stopIsClip =
      clipEnd != null && Number.isFinite(clipEnd) && clipEnd < tapeEnd - 0.5;
    if (mode === "auto") {
      const peak = peakExcitementAhead(tape, playheadMsRef.current);
      let target = speedFromExcitement(peak);
      if (playheadMsRef.current < slowHoldUntilRef.current) {
        target = Math.min(target, 0.38);
      }
      // Плавный вход/выход из slow-mo — без рывков ×3→×0.2.
      const blend = target < smoothSpeedRef.current ? 0.22 : 0.1;
      smoothSpeedRef.current += (target - smoothSpeedRef.current) * blend;
      speed = smoothSpeedRef.current;
    } else {
      speed = mode;
      smoothSpeedRef.current = mode;
    }

    if (playingRef.current) {
      const fromMs = playheadMsRef.current;
      playheadMsRef.current = Math.min(
        endMs,
        playheadMsRef.current + dt * speed,
      );
      const toMs = playheadMsRef.current;
      const fire = onReplayEventRef.current;
      if (fire) {
        for (const event of tape.eventsBetween(fromMs, toMs)) {
          if (event.damage >= 10 || event.kind === "ko") {
            slowHoldUntilRef.current = Math.max(
              slowHoldUntilRef.current,
              event.t + REPLAY_HIT_HOLD_MS,
            );
          }
          fire(event);
        }
      }
      if (playheadMsRef.current >= endMs - 0.5) {
        playheadMsRef.current = endMs;
        if (playingRef.current) {
          playingRef.current = false;
          setPlaying(false);
          if (!stopIsClip && !endedFiredRef.current) {
            endedFiredRef.current = true;
            onEndedRef.current?.();
          }
        }
      }
    }

    const bodies = opts.getBodies();
    const need = Math.max(bodies.length, 1) * 3;
    let scratch = poseScratchRef.current;
    if (!scratch || scratch.length < need) {
      scratch = new Float32Array(need);
      poseScratchRef.current = scratch;
    }
    tape.samplePosesAt(playheadMsRef.current, scratch);
    applyFightTapePoses(bodies, scratch);
    const idx = tape.indexFloorAtTime(playheadMsRef.current);

    if (now - lastUiRef.current > 80) {
      lastUiRef.current = now;
      setEffectiveSpeed(Math.round(speed * 10) / 10);
      setUi({
        playheadRatio: endMs > 0 ? playheadMsRef.current / endMs : 0,
        playheadMs: playheadMsRef.current,
        frameIndex: idx,
        durationMs: endMs,
        frameCount: tape.frameCount,
      });
    }
  }, [opts.enabled, opts.getBodies, opts.tapeRef, engine]);

  const seekRatio = useCallback(
    (ratio: number) => {
      const tape = opts.tapeRef.current;
      if (!tape) return;
      const endMs = tape.playbackEndMs;
      const t = Math.max(0, Math.min(1, ratio)) * endMs;
      const prev = playheadMsRef.current;
      playheadMsRef.current = t;
      slowHoldUntilRef.current = 0;
      endedFiredRef.current = t >= endMs - 0.5;
      const bodies = opts.getBodies();
      const need = Math.max(bodies.length, 1) * 3;
      let scratch = poseScratchRef.current;
      if (!scratch || scratch.length < need) {
        scratch = new Float32Array(need);
        poseScratchRef.current = scratch;
      }
      tape.samplePosesAt(t, scratch);
      applyFightTapePoses(bodies, scratch);
      const idx = tape.indexFloorAtTime(t);
      if (t < prev - 1) {
        onClearReplayFxRef.current?.();
      } else if (t > prev + 1) {
        const fire = onReplayEventRef.current;
        if (fire) {
          for (const event of tape.eventsBetween(prev, t)) fire(event);
        }
      }
      const peak = peakExcitementAhead(tape, t);
      const mode = speedModeRef.current;
      const speed = mode === "auto" ? speedFromExcitement(peak) : mode;
      smoothSpeedRef.current = speed;
      setEffectiveSpeed(Math.round(speed * 10) / 10);
      setUi({
        playheadRatio: endMs > 0 ? t / endMs : 0,
        playheadMs: t,
        frameIndex: idx,
        durationMs: endMs,
        frameCount: tape.frameCount,
      });
    },
    [opts.getBodies, opts.tapeRef],
  );

  const togglePlay = useCallback(() => {
    setPlaying((p) => {
      if (!p) {
        const tape = opts.tapeRef.current;
        const endMs = tape?.playbackEndMs ?? 0;
        if (tape && playheadMsRef.current >= endMs - 0.5) {
          playheadMsRef.current = 0;
          slowHoldUntilRef.current = 0;
          smoothSpeedRef.current = 1.6;
          endedFiredRef.current = false;
          onClearReplayFxRef.current?.();
        }
        lastTickRef.current = performance.now();
      }
      return !p;
    });
  }, [opts.tapeRef]);

  return {
    playing,
    speedMode,
    setSpeedMode,
    /** Текущая фактическая скорость (auto или ручная). */
    speed: effectiveSpeed,
    ...ui,
    sampleHz: FIGHT_TAPE_HZ,
    togglePlay,
    seekRatio,
    wave,
  };
}
