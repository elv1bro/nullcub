import { drawAvatarFacePreview } from "@/face/drawAvatarFace";
import type { AvatarFacePreset } from "@/face/avatarPresets";
import { useEffect, useRef } from "react";

const PREVIEW_SIZE = 52;

/** Превью лица в чипе карусели. Рисуется лениво — когда чип доскроллили до видимости. */
export function AvatarFaceChipCanvas({ preset }: { preset: AvatarFacePreset }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let drawn = false;
    const draw = (): void => {
      if (drawn) return;
      drawn = true;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      const dpr = Math.min(window.devicePixelRatio || 1, 3);
      const px = Math.round(PREVIEW_SIZE * dpr);
      if (canvas.width !== px) {
        canvas.width = px;
        canvas.height = px;
      }
      drawAvatarFacePreview(ctx, px, preset);
    };
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          draw();
          io.disconnect();
        }
      },
      { rootMargin: "384px" },
    );
    io.observe(canvas);
    return () => io.disconnect();
  }, [preset]);

  return (
    <canvas
      ref={canvasRef}
      width={PREVIEW_SIZE}
      height={PREVIEW_SIZE}
      className="menu-avatar-chip__canvas"
      aria-hidden
    />
  );
}
