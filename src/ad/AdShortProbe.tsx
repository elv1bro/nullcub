import { installAdProbeApi } from "@/ad/adProbeScene";
import { MENU_TRACK } from "@/audio/music";
import { useEffect, useRef } from "react";

/**
 * Изолированный экран для рекламного эксперимента.
 * Открыть: `/?ad=probe` — Play сам / Puppeteer пишет mp4.
 */
export function AdShortProbe() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const api = installAdProbeApi(canvas);
    const mode = new URLSearchParams(window.location.search).get("record");

    // Для ручного просмотра — трек меню; в mp4 музыка вшивается в yarn ad:probe.
    let menuAudio: HTMLAudioElement | null = null;
    const startMenuMusic = () => {
      menuAudio = new Audio(MENU_TRACK.url);
      menuAudio.loop = true;
      menuAudio.volume = 0.55;
      void menuAudio.play().catch(() => undefined);
    };

    // record=wait — только API (Puppeteer сам вызовет record).
    // record=1 — сразу писать. Иначе — play для ручного просмотра.
    if (mode === "1") void api.record();
    else if (mode !== "wait") {
      startMenuMusic();
      void api.play();
    }
    return () => {
      menuAudio?.pause();
      menuAudio = null;
      delete window.__RAGDOLL_AD__;
    };
  }, []);

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "#050508",
        display: "grid",
        placeItems: "center",
        overflow: "hidden",
      }}
    >
      <canvas
        ref={canvasRef}
        width={1080}
        height={1920}
        style={{
          width: "min(100vw, calc(100vh * 9 / 16))",
          height: "min(100vh, calc(100vw * 16 / 9))",
          background: "#050508",
        }}
      />
    </div>
  );
}
