import { useFaceTracker } from "@/face/tracker";
import { useNetSession } from "./NetSessionContext";
import { useEffect, useRef } from "react";
import type { FacePrivacyMode } from "./protocol";

/** Отправка crop + emotion по data-каналу; видео/аудио — через addStream. */
export function useNetFaceSync(
  faceMode: FacePrivacyMode,
  enabled: boolean,
): ReturnType<typeof useFaceTracker> {
  const net = useNetSession();
  const face = useFaceTracker({
    enabled,
    audio: faceMode !== "none",
    tracking: faceMode === "tracking",
  });
  const lastCropSent = useRef(0);
  const faceRef = useRef(face);
  faceRef.current = face;

  useEffect(() => {
    if (!enabled || !net.localStream || !face.streamRef.current) return;
    net.setLocalMedia(face.streamRef.current);
  }, [enabled, face.streamRef, net]);

  useEffect(() => {
    if (!enabled || !net.actions) return;
    const [sendEmotion] = net.actions.emotion;
    const [sendCrop] = net.actions.crop;
    let raf = 0;
    const tick = () => {
      const f = faceRef.current;
      const now = performance.now();
      const frame = f.frameRef.current ?? f.frame;
      if (frame && faceMode !== "none") {
        sendEmotion({
          fighterId: "local",
          emotion: frame.emotion,
          intensity: frame.intensity,
        });
      }
      if (f.cropRef.current && faceMode === "video" && now - lastCropSent.current > 66) {
        lastCropSent.current = now;
        const c = f.cropRef.current;
        sendCrop({
          fighterId: "local",
          x: c.sx,
          y: c.sy,
          w: c.sw,
          h: c.sh,
        });
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [enabled, net.actions, faceMode]);

  return face;
}
