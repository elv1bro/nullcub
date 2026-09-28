import {
  drawBattleBackdrop,
  pickBattleBackdrop,
  type BattleBackdropId,
} from "@/render/battleBackdrops";
import { useRender, useRenderEvent } from "@1.framework/matter4react";
import { useEffect, useRef } from "react";

/** Фон арены перерисовываем ~30 Hz, в кадр — дешёвый drawImage. */
const BACKDROP_REDRAW_MS = 33;

/**
 * Фон арены: Matter canvas прозрачный, картинка — destination-over.
 * Тема выбирается один раз на mount (новый бой → новый рандом).
 */
export function BattleSpaceBg({
  theme: themeProp,
  suddenDeath = false,
}: {
  /** Зафиксировать тему (e2e / дебаг). Иначе — random на mount. */
  theme?: BattleBackdropId;
  /** Красное «небо» sudden death — в бою и в повторе. */
  suddenDeath?: boolean;
} = {}) {
  const render = useRender();
  const themeRef = useRef<BattleBackdropId>(themeProp ?? pickBattleBackdrop());
  const suddenRef = useRef(suddenDeath);
  const bufRef = useRef<HTMLCanvasElement | null>(null);
  const lastDrawRef = useRef(0);
  if (themeProp) themeRef.current = themeProp;
  suddenRef.current = suddenDeath;

  useEffect(() => {
    const prev = render.options.background;
    render.options.background = "transparent";
    return () => {
      render.options.background = prev;
    };
  }, [render]);

  useRenderEvent(
    "afterRender",
    () => {
      const ctx = render.context;
      if (!ctx) return;
      const w = render.canvas?.width ?? 0;
      const h = render.canvas?.height ?? 0;
      if (w < 2 || h < 2) return;

      let buf = bufRef.current;
      if (!buf) {
        buf = document.createElement("canvas");
        bufRef.current = buf;
      }
      if (buf.width !== w || buf.height !== h) {
        buf.width = w;
        buf.height = h;
        lastDrawRef.current = 0;
      }

      const now = performance.now();
      if (now - lastDrawRef.current >= BACKDROP_REDRAW_MS) {
        lastDrawRef.current = now;
        const bctx = buf.getContext("2d");
        if (bctx) {
          drawBattleBackdrop(bctx, w, h, now, themeRef.current);
          if (suddenRef.current) {
            const pulse = 0.22 + Math.sin(now * 0.008) * 0.08;
            const grad = bctx.createRadialGradient(
              w * 0.5,
              h * 0.35,
              Math.min(w, h) * 0.1,
              w * 0.5,
              h * 0.5,
              Math.max(w, h) * 0.75,
            );
            grad.addColorStop(0, `rgba(255, 60, 40, ${pulse * 0.55})`);
            grad.addColorStop(0.55, `rgba(120, 10, 30, ${pulse})`);
            grad.addColorStop(1, `rgba(10, 0, 8, ${0.55 + pulse})`);
            bctx.fillStyle = grad;
            bctx.fillRect(0, 0, w, h);
            bctx.globalAlpha = 0.18 + pulse * 0.25;
            bctx.fillStyle = "#ff2a1a";
            bctx.fillRect(0, 0, w, h * 0.12);
            bctx.globalAlpha = 1;
          }
        }
      }

      ctx.save();
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalCompositeOperation = "destination-over";
      ctx.drawImage(buf, 0, 0);
      ctx.restore();
    },
    [render],
  );

  return null;
}
