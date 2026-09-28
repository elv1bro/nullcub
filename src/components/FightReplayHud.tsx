import {
  REPLAY_SPEEDS,
  type ReplaySpeedMode,
} from "@/lib/useFightReplay";
import { findExcitementPeaks } from "@/lib/fightTape";
import type { FightTape } from "@/lib/fightTape";
import { copyFightClipShare } from "@/lib/fightClipShare";
import { useSettings } from "@/settings/SettingsContext";
import {
  useCallback,
  useMemo,
  useRef,
  useState,
  type MutableRefObject,
  type PointerEvent,
} from "react";

interface Props {
  wave: number[];
  playheadRatio: number;
  playheadMs: number;
  durationMs: number;
  playing: boolean;
  speedMode: ReplaySpeedMode;
  /** Фактическая скорость сейчас (для Auto показывает 0.3…8). */
  speed: number;
  tapeRef: MutableRefObject<FightTape | null | undefined>;
  onTogglePlay: () => void;
  onSpeedMode: (mode: ReplaySpeedMode) => void;
  onSeekRatio: (ratio: number) => void;
  onFinish: () => void;
  /** Ограничить воспроизведение концом клипа (мс). */
  onClipWindow?: (fromMs: number | null, toMs: number | null) => void;
}

function formatTime(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = String(total % 60).padStart(2, "0");
  return `${m}:${s}`;
}

function formatSpeed(speed: number): string {
  if (speed >= 10) return `×${Math.round(speed)}`;
  const rounded = Math.round(speed * 10) / 10;
  return Number.isInteger(rounded) ? `×${rounded}` : `×${rounded.toFixed(1)}`;
}

export function FightReplayHud({
  wave,
  playheadRatio,
  playheadMs,
  durationMs,
  playing,
  speedMode,
  speed,
  tapeRef,
  onTogglePlay,
  onSpeedMode,
  onSeekRatio,
  onFinish,
  onClipWindow,
}: Props) {
  const { t } = useSettings();
  const trackRef = useRef<HTMLDivElement>(null);
  const [markIn, setMarkIn] = useState<number | null>(null);
  const [markOut, setMarkOut] = useState<number | null>(null);
  const [shareHint, setShareHint] = useState<string | null>(null);

  const peaks = useMemo(() => findExcitementPeaks(wave, 0.42), [wave]);

  const pathD = useMemo(() => {
    if (wave.length === 0) return "";
    const w = 100;
    const h = 36;
    const step = w / Math.max(1, wave.length - 1);
    let d = `M 0 ${h}`;
    for (let i = 0; i < wave.length; i++) {
      const x = i * step;
      const y = h - wave[i]! * (h - 2);
      d += ` L ${x.toFixed(2)} ${y.toFixed(2)}`;
    }
    d += ` L ${w} ${h} Z`;
    return d;
  }, [wave]);

  const sel = useMemo(() => {
    if (markIn == null || markOut == null || durationMs <= 0) return null;
    const a = Math.min(markIn, markOut);
    const b = Math.max(markIn, markOut);
    return {
      left: (a / durationMs) * 100,
      width: ((b - a) / durationMs) * 100,
      from: a,
      to: b,
    };
  }, [markIn, markOut, durationMs]);

  const seekFromClientX = useCallback(
    (clientX: number) => {
      const el = trackRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const ratio = (clientX - rect.left) / Math.max(1, rect.width);
      onSeekRatio(ratio);
    },
    [onSeekRatio],
  );

  const onPointerDown = (e: PointerEvent<HTMLDivElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    seekFromClientX(e.clientX);
  };
  const onPointerMove = (e: PointerEvent<HTMLDivElement>) => {
    if (!e.currentTarget.hasPointerCapture(e.pointerId)) return;
    seekFromClientX(e.clientX);
  };

  const setIn = () => {
    setMarkIn(playheadMs);
    setShareHint(null);
    if (markOut != null) onClipWindow?.(Math.min(playheadMs, markOut), Math.max(playheadMs, markOut));
  };
  const setOut = () => {
    setMarkOut(playheadMs);
    setShareHint(null);
    if (markIn != null) onClipWindow?.(Math.min(markIn, playheadMs), Math.max(markIn, playheadMs));
  };
  const clearMarks = () => {
    setMarkIn(null);
    setMarkOut(null);
    setShareHint(null);
    onClipWindow?.(null, null);
  };

  const shareClip = async () => {
    const tape = tapeRef.current;
    if (!tape || markIn == null || markOut == null) {
      setShareHint(t.battle.replayClipNeedMarks);
      return;
    }
    const from = Math.min(markIn, markOut);
    const to = Math.max(markIn, markOut);
    if (to - from < 200) {
      setShareHint(t.battle.replayClipNeedMarks);
      return;
    }
    const clip = tape.exportClip(from, to);
    const ok = await copyFightClipShare(clip);
    setShareHint(ok ? t.battle.replayClipCopied : t.battle.replayClipFailed);
  };

  return (
    <div className="fight-replay-hud pointer-events-auto">
      <div className="fight-replay-hud__chrome">
        <div className="fight-replay-hud__title font-display">
          {t.battle.replayTitle}
        </div>
        <span className="fight-replay-hud__time font-ui">
          {formatSpeed(speed)} · {formatTime(playheadMs)} /{" "}
          {formatTime(durationMs)}
        </span>
      </div>

      <div
        ref={trackRef}
        className="fight-replay-wave"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        role="slider"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(playheadRatio * 100)}
        aria-label={t.battle.replayScrub}
      >
        <svg
          className="fight-replay-wave__svg"
          viewBox="0 0 100 36"
          preserveAspectRatio="none"
        >
          <path className="fight-replay-wave__fill" d={pathD} />
        </svg>
        {sel && (
          <span
            className="fight-replay-wave__selection"
            style={{ left: `${sel.left}%`, width: `${sel.width}%` }}
          />
        )}
        {markIn != null && durationMs > 0 && (
          <span
            className="fight-replay-wave__mark fight-replay-wave__mark--in"
            style={{ left: `${(markIn / durationMs) * 100}%` }}
          />
        )}
        {markOut != null && durationMs > 0 && (
          <span
            className="fight-replay-wave__mark fight-replay-wave__mark--out"
            style={{ left: `${(markOut / durationMs) * 100}%` }}
          />
        )}
        {peaks.map((i) => (
          <button
            key={i}
            type="button"
            className="fight-replay-wave__peak"
            style={{ left: `${(i / Math.max(1, wave.length - 1)) * 100}%` }}
            aria-label={t.battle.replayScrub}
            onClick={(e) => {
              e.stopPropagation();
              onSeekRatio(i / Math.max(1, wave.length - 1));
            }}
          />
        ))}
        <span
          className="fight-replay-wave__playhead"
          style={{ left: `${playheadRatio * 100}%` }}
        />
      </div>

      <div className="fight-replay-hud__clip font-ui">
        <button type="button" className="fight-replay-clip-btn" onClick={setIn}>
          {t.battle.replayMarkIn}
        </button>
        <button type="button" className="fight-replay-clip-btn" onClick={setOut}>
          {t.battle.replayMarkOut}
        </button>
        <button
          type="button"
          className="fight-replay-clip-btn"
          onClick={() => void shareClip()}
          disabled={markIn == null || markOut == null}
        >
          {t.battle.replayShareClip}
        </button>
        <button
          type="button"
          className="fight-replay-clip-btn"
          onClick={clearMarks}
          disabled={markIn == null && markOut == null}
        >
          {t.battle.replayClearClip}
        </button>
        {shareHint && (
          <span className="fight-replay-hud__share-hint">{shareHint}</span>
        )}
      </div>

      <div className="fight-replay-hud__row">
        <button
          type="button"
          className="menu-nav-btn text-sm! fight-replay-hud__play"
          onClick={onTogglePlay}
        >
          {playing ? t.battle.replayPause : t.battle.replayPlay}
        </button>

        <div className="fight-replay-hud__speeds">
          <button
            type="button"
            className={[
              "fight-replay-speed",
              speedMode === "auto" ? "fight-replay-speed--active" : "",
            ].join(" ")}
            onClick={() => onSpeedMode("auto")}
          >
            {t.battle.replayAuto}
          </button>
          {REPLAY_SPEEDS.map((s) => (
            <button
              key={s}
              type="button"
              className={[
                "fight-replay-speed",
                speedMode === s ? "fight-replay-speed--active" : "",
              ].join(" ")}
              onClick={() => onSpeedMode(s)}
            >
              ×{s}
            </button>
          ))}
        </div>

        <button
          type="button"
          className="menu-nav-btn menu-nav-btn--primary text-sm! fight-replay-hud__finish"
          onClick={onFinish}
        >
          {t.battle.replayToRecap}
        </button>
      </div>
    </div>
  );
}
