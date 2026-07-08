import { useEffect, useRef } from "react";

interface Spark {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  maxLife: number;
  size: number;
}

interface Props {
  accentColor?: string;
}

function parseHue(hex: string): number {
  const h = hex.replace("#", "");
  if (h.length < 6) return 200;
  const r = parseInt(h.slice(0, 2), 16) / 255;
  const g = parseInt(h.slice(2, 4), 16) / 255;
  const b = parseInt(h.slice(4, 6), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max === min) return 200;
  let hue = 0;
  const d = max - min;
  if (max === r) hue = ((g - b) / d + (g < b ? 6 : 0)) / 6;
  else if (max === g) hue = ((b - r) / d + 2) / 6;
  else hue = ((r - g) / d + 4) / 6;
  return hue * 360;
}

/** Искры у пола — accent игрока, не rainbow. */
export function MenuSparkField({ accentColor = "#38bdf8" }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const hueRef = useRef(parseHue(accentColor));

  useEffect(() => {
    hueRef.current = parseHue(accentColor);
  }, [accentColor]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let raf = 0;
    let w = 0;
    let h = 0;
    const sparks: Spark[] = [];

    const resize = () => {
      w = canvas.width = window.innerWidth;
      h = canvas.height = window.innerHeight;
    };
    resize();
    window.addEventListener("resize", resize);

    const spawn = () => {
      if (sparks.length > 80) return;
      sparks.push({
        x: Math.random() * w,
        y: h * 0.88 + Math.random() * 40,
        vx: (Math.random() - 0.5) * 1.4,
        vy: -(1.2 + Math.random() * 2),
        life: 0,
        maxLife: 70 + Math.random() * 90,
        size: 1 + Math.random() * 2,
      });
    };

    const draw = () => {
      ctx.clearRect(0, 0, w, h);
      if (Math.random() < 0.45) spawn();

      const baseHue = hueRef.current;
      for (let i = sparks.length - 1; i >= 0; i--) {
        const s = sparks[i]!;
        s.life += 1;
        s.x += s.vx;
        s.y += s.vy;
        s.vy += 0.012;

        const t = s.life / s.maxLife;
        const alpha = (1 - t) * 0.7;
        const hue = baseHue + (Math.random() - 0.5) * 16;

        ctx.save();
        ctx.globalAlpha = alpha;
        ctx.strokeStyle = `hsl(${hue}, 85%, 62%)`;
        ctx.lineWidth = s.size;
        ctx.beginPath();
        ctx.moveTo(s.x, s.y);
        ctx.lineTo(s.x - s.vx * 3, s.y - s.vy * 3);
        ctx.stroke();
        ctx.restore();

        if (s.life >= s.maxLife || s.y < h * 0.5) sparks.splice(i, 1);
      }

      raf = requestAnimationFrame(draw);
    };

    raf = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="fixed inset-0 pointer-events-none z-0"
      aria-hidden
    />
  );
}
