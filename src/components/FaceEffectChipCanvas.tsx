import { drawFaceEffectPreview } from "@/face/faceEffects";
import type { FaceOverlayEffectId } from "@/face/faceEffects";
import { useEffect, useRef } from "react";

const PREVIEW_SIZE = 52;

export function FaceEffectChipCanvas({
  effectId,
}: {
  effectId: FaceOverlayEffectId;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let raf = 0;
    const draw = () => {
      drawFaceEffectPreview(ctx, PREVIEW_SIZE, effectId, performance.now());
      if (effectId !== "none") {
        raf = requestAnimationFrame(draw);
      }
    };
    draw();
    return () => cancelAnimationFrame(raf);
  }, [effectId]);

  return (
    <canvas
      ref={canvasRef}
      width={PREVIEW_SIZE}
      height={PREVIEW_SIZE}
      className="menu-effect-chip__canvas"
      aria-hidden
    />
  );
}
