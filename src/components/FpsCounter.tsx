import { useEffect, useRef } from "react";

/**
 * Счётчик FPS в углу. Пишет прямо в DOM — без React setState каждый
 * полсекунды, чтобы сам оверлей не добавлял лишних ререндеров.
 */
export function FpsCounter() {
  const labelRef = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    let frames = 0;
    let last = performance.now();
    let raf = 0;

    const tick = (now: number) => {
      frames += 1;
      const elapsed = now - last;
      if (elapsed >= 500) {
        const fps = Math.round((frames * 1000) / elapsed);
        frames = 0;
        last = now;
        const el = labelRef.current;
        if (el) {
          el.textContent = `${fps} FPS`;
          el.classList.toggle("text-emerald-300", fps >= 55);
          el.classList.toggle("text-amber-300", fps >= 30 && fps < 55);
          el.classList.toggle("text-rose-400", fps < 30);
        }
      }
      raf = requestAnimationFrame(tick);
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div
      className="pointer-events-none fixed top-3 left-3 z-50 font-ui tabular-nums"
      aria-live="off"
      data-testid="fps-counter"
    >
      <span
        ref={labelRef}
        className="block bg-black/55 px-2 py-0.5 rounded text-xs tracking-wide text-amber-300"
      >
        — FPS
      </span>
    </div>
  );
}
