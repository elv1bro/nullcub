import { Loading } from "@/components/Loading";
import { LOADER_DOLL_COUNT, createSplashScene } from "@/lib/splashScene";
import { useTranslation } from "@/settings/SettingsContext";
import { useEffect, useRef, useState } from "react";

/** Переход между экранами обычно короче — не мигаем толпой почём зря. */
const APPEAR_DELAY_MS = 250;

function prefersReducedMotion(): boolean {
  return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
}

function isE2E(): boolean {
  return new URLSearchParams(window.location.search).has("e2e");
}

/**
 * Загрузочный экран: тот же логотип, что на заставке, только уже собранный, и
 * на него бесконечно сыплются бойцы. Пока экран грузится быстро, показывается
 * обычная крутилка — толпа появляется, только если ждать и правда приходится.
 */
export function RagdollLoader() {
  const t = useTranslation();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [rich, setRich] = useState(false);

  useEffect(() => {
    if (isE2E() || navigator.webdriver || prefersReducedMotion()) return;
    const timer = window.setTimeout(() => setRich(true), APPEAR_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!rich) return;
    const canvas = canvasRef.current;
    if (!canvas) return;

    const scene = createSplashScene({
      canvas,
      words: [
        { text: t.game.title, accent: false },
        { text: t.game.titleAccent, accent: true },
      ],
      accentColor:
        getComputedStyle(document.documentElement)
          .getPropertyValue("--menu-accent")
          .trim() || "#38bdf8",
      dollCount: LOADER_DOLL_COUNT,
      assembled: true,
      loop: true,
    });
    // Сломавшийся лоадер не должен прятать загрузку — просто останется пусто.
    scene.start().catch(() => undefined);
    return () => scene.stop();
  }, [rich, t.game.title, t.game.titleAccent]);

  if (!rich) {
    return (
      <div className="vstack h-100% items-center justify-center">
        <Loading />
      </div>
    );
  }

  return (
    <div className="boot-splash boot-splash--loader" aria-busy="true">
      <canvas ref={canvasRef} className="boot-splash__canvas" />
      <p className="boot-splash__tagline font-ui">{t.account.loading}</p>
    </div>
  );
}
