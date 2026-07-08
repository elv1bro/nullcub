import { useSettings } from "@/settings/SettingsContext";
import { useEffect, useRef, useState } from "react";
import {
  getNowPlaying,
  prevBattleTrack,
  skipBattleTrack,
  subscribeNowPlaying,
  type MusicTrack,
} from "./music";

/**
 * Виджет «сейчас играет» (как трек-анонс в FlatOut 2): при смене трека
 * разворачивается с названием, затем сжимается до компактной панели
 * с регулировкой громкости.
 */
export function NowPlaying() {
  const { t, settings, setMusicVolume, setMusicEnabled } = useSettings();
  const [track, setTrack] = useState<MusicTrack | null>(getNowPlaying);
  const [announce, setAnnounce] = useState(false);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    const unsub = subscribeNowPlaying((next) => {
      setTrack(next);
      if (!next) return;
      setAnnounce(true);
      if (timerRef.current !== null) clearTimeout(timerRef.current);
      timerRef.current = window.setTimeout(() => setAnnounce(false), 4500);
    });
    return () => {
      unsub();
      if (timerRef.current !== null) clearTimeout(timerRef.current);
    };
  }, []);

  if (!track) return null;

  const pct = Math.round(settings.musicVolume * 100);
  const nudge = (delta: number) =>
    setMusicVolume(Math.round((settings.musicVolume + delta) * 10) / 10);

  return (
    <div
      className={[
        "now-playing font-ui",
        announce ? "now-playing--announce" : "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <span className="now-playing__note" aria-hidden>
        ♪
      </span>
      <span className="now-playing__label" title={t.music.nowPlaying}>
        {track.title} — {track.artist}
      </span>
      <div className="now-playing__controls">
        <button
          type="button"
          className="now-playing__btn"
          title={t.music.prev}
          onClick={prevBattleTrack}
        >
          ≪
        </button>
        <button
          type="button"
          className="now-playing__btn"
          title={t.music.quieter}
          onClick={() => nudge(-0.1)}
        >
          −
        </button>
        <span className="now-playing__pct">
          {settings.musicEnabled ? `${pct}%` : t.music.off}
        </span>
        <button
          type="button"
          className="now-playing__btn"
          title={t.music.louder}
          onClick={() => nudge(0.1)}
        >
          +
        </button>
        <button
          type="button"
          className="now-playing__btn now-playing__btn--wide"
          title={settings.musicEnabled ? t.music.mute : t.music.unmute}
          onClick={() => setMusicEnabled(!settings.musicEnabled)}
        >
          {settings.musicEnabled ? t.music.muteShort : t.music.unmuteShort}
        </button>
        <button
          type="button"
          className="now-playing__btn"
          title={t.music.next}
          onClick={skipBattleTrack}
        >
          ≫
        </button>
      </div>
    </div>
  );
}
