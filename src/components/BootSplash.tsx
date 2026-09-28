import { audioContext } from "@/audio";
import {
  SPLASH_DOLL_COUNT,
  SPLASH_FADE_MS,
  createSplashScene,
  type SplashScene,
} from "@/lib/splashScene";
import { useTranslation } from "@/settings/SettingsContext";
import { useEffect, useRef, useState } from "react";

function prefersReducedMotion(): boolean {
  return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
}

/** Заставка перехватывает клики Puppeteer, а в e2e-сценариях она не нужна. */
function isE2E(): boolean {
  return new URLSearchParams(window.location.search).has("e2e");
}

function shouldSkip(): boolean {
  // navigator.webdriver — скриншотные и e2e-прогоны: заставка съела бы клик.
  return isE2E() || navigator.webdriver || prefersReducedMotion();
}

async function unlockAudio(): Promise<void> {
  const ctx = audioContext();
  if (!ctx) return;
  if (ctx.state === "suspended") {
    try {
      await ctx.resume();
    } catch {
      // браузер отказал — звук просто не будет
    }
  }
}

/**
 * Экран запуска:
 * 1) буквы падают и собираются в логотип;
 * 2) пульсирует «Нажми, чтобы начать»;
 * 3) тап разблокирует звук и запускает дождь бойцов → fade → меню/логин.
 */
export function BootSplash({ onFinished }: { onFinished?: () => void }) {
  const t = useTranslation();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<SplashScene | null>(null);
  const onFinishedRef = useRef(onFinished);
  onFinishedRef.current = onFinished;
  const [hidden, setHidden] = useState(() => shouldSkip());
  const [fading, setFading] = useState(false);
  const [awaitingTap, setAwaitingTap] = useState(false);
  const [raining, setRaining] = useState(false);

  useEffect(() => {
    if (hidden) {
      onFinishedRef.current?.();
      return;
    }
    const canvas = canvasRef.current;
    if (!canvas) return;

    let doneTimer = 0;
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      setFading(true);
      setAwaitingTap(false);
      doneTimer = window.setTimeout(() => {
        setHidden(true);
        onFinishedRef.current?.();
      }, SPLASH_FADE_MS);
    };

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
      dollCount: SPLASH_DOLL_COUNT,
      waitForTap: true,
      onAwaitingTap: () => setAwaitingTap(true),
      onDone: finish,
    });
    sceneRef.current = scene;

    // Сломавшаяся заставка не должна закрывать собой игру.
    scene.start().catch(() => {
      setHidden(true);
      onFinishedRef.current?.();
    });

    return () => {
      window.clearTimeout(doneTimer);
      scene.stop();
      sceneRef.current = null;
    };
  }, [hidden, t.game.title, t.game.titleAccent]);

  // Отдельный эффект на тап: состояние awaitingTap/raining актуально.
  useEffect(() => {
    if (hidden || fading) return;
    const onTap = () => {
      const s = sceneRef.current;
      if (!s) return;
      if (awaitingTap && !raining) {
        setAwaitingTap(false);
        setRaining(true);
        void unlockAudio().then(() => s.beginRain());
        return;
      }
      if (raining) s.finishNow();
    };
    window.addEventListener("pointerdown", onTap);
    window.addEventListener("keydown", onTap);
    return () => {
      window.removeEventListener("pointerdown", onTap);
      window.removeEventListener("keydown", onTap);
    };
  }, [hidden, fading, awaitingTap, raining]);

  if (hidden) return null;

  return (
    <div
      className={`boot-splash${fading ? " boot-splash--out" : ""}`}
      aria-hidden="true"
    >
      <canvas ref={canvasRef} className="boot-splash__canvas" />
      {awaitingTap ? (
        <p className="boot-splash__tap font-ui">{t.game.tapToStart}</p>
      ) : (
        <p className="boot-splash__tagline font-ui">{t.game.subtitle}</p>
      )}
    </div>
  );
}
