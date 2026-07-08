import {
  FaceLandmarker,
  FilesetResolver,
  type FaceLandmarkerResult,
} from "@mediapipe/tasks-vision";
import { useEffect, useRef, useState, type RefObject } from "react";
import {
  centerCrop,
  landmarksToCrop,
  smoothCrop,
  type FaceCropRect,
} from "./faceCrop";
import { detectEmotion, type FaceState } from "./emotions";

const WASM =
  "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/wasm";
const MODEL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

function resultToBlendshapes(result: FaceLandmarkerResult): Record<string, number> {
  const categories = result.faceBlendshapes?.[0]?.categories;
  if (!categories) return {};
  return Object.fromEntries(
    categories.map((c) => [c.categoryName, c.score]),
  );
}

export interface FaceTrackerState {
  ready: boolean;
  error: string | null;
  frame: FaceState | null;
  /** Актуальный кадр эмоции без React re-render (для net sync). */
  frameRef: RefObject<FaceState | null>;
  videoRef: RefObject<HTMLVideoElement>;
  /** Актуальный кроп лица — обновляется каждый кадр без ре-рендера React. */
  cropRef: RefObject<FaceCropRect | null>;
  /** MediaStream для WebRTC (видео ± аудио). */
  streamRef: RefObject<MediaStream | null>;
}

export interface FaceTrackerOptions {
  enabled?: boolean;
  /** Запрашивать микрофон вместе с камерой (сеть). */
  audio?: boolean;
  /** MediaPipe (мимика + кроп по landmarks). false = только видеопоток. */
  tracking?: boolean;
}

/** Вебка → MediaPipe blendshapes → эмоция игрока. */
export function useFaceTracker(options: FaceTrackerOptions | boolean = true): FaceTrackerState {
  const opts = typeof options === "boolean" ? { enabled: options } : options;
  const enabled = opts.enabled ?? true;
  const withAudio = opts.audio === true;
  const withTracking = enabled && opts.tracking === true;
  const videoRef = useRef<HTMLVideoElement>(null);
  const cropRef = useRef<FaceCropRect | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const frameRef = useRef<FaceState | null>(null);
  const landmarkerRef = useRef<FaceLandmarker | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [frame, setFrame] = useState<FaceState | null>(null);

  useEffect(() => {
    if (!enabled && !withAudio) {
      setReady(false);
      setError(null);
      setFrame(null);
      cropRef.current = null;
      return;
    }

    let cancelled = false;
    let raf = 0;
    let stream: MediaStream | null = null;

    async function init() {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: enabled
            ? { facingMode: "user", width: 640, height: 480 }
            : false,
          audio: withAudio,
        });
        streamRef.current = stream;
        const video = videoRef.current;
        if (cancelled) return;

        if (enabled && video) {
          video.srcObject = stream;
          video.playsInline = true;
          video.muted = true;
          await video.play();

          if (withTracking) {
            const vision = await FilesetResolver.forVisionTasks(WASM);
            const landmarker = await FaceLandmarker.createFromOptions(vision, {
              baseOptions: { modelAssetPath: MODEL, delegate: "GPU" },
              runningMode: "VIDEO",
              numFaces: 1,
              outputFaceBlendshapes: true,
            });
            if (cancelled) return;
            landmarkerRef.current = landmarker;

            let lastVideoTime = -1;
            let lastFrameUiAt = 0;
            const tick = () => {
              if (cancelled || !landmarkerRef.current || !videoRef.current) return;
              const v = videoRef.current;
              if (v.readyState >= 2 && v.currentTime !== lastVideoTime) {
                lastVideoTime = v.currentTime;
                const now = performance.now();
                const result = landmarkerRef.current.detectForVideo(v, now);
                const blendshapes = resultToBlendshapes(result);
                const landmarks = result.faceLandmarks?.[0];

                if (landmarks?.length) {
                  const raw = landmarksToCrop(
                    landmarks,
                    v.videoWidth,
                    v.videoHeight,
                  );
                  if (raw) {
                    cropRef.current = smoothCrop(cropRef.current, raw);
                  }
                } else if (!cropRef.current && v.videoWidth > 0) {
                  cropRef.current = centerCrop(v.videoWidth, v.videoHeight);
                }

                if (Object.keys(blendshapes).length > 0) {
                  // Ref — без React re-render на каждый кадр; setFrame ~10Hz.
                  const next = detectEmotion(blendshapes);
                  frameRef.current = next;
                  if (now - lastFrameUiAt > 100) {
                    lastFrameUiAt = now;
                    setFrame(next);
                  }
                }
              }
              raf = requestAnimationFrame(tick);
            };
            raf = requestAnimationFrame(tick);
          } else if (video.videoWidth > 0) {
            cropRef.current = centerCrop(video.videoWidth, video.videoHeight);
          }

          setReady(true);
          if (!withTracking) {
            setFrame(detectEmotion({}, "neutral"));
          }
        } else if (withAudio) {
          setReady(true);
          setFrame(detectEmotion({}, "neutral"));
        }
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : "Не удалось включить вебку");
          setFrame(detectEmotion({}, "neutral"));
        }
      }
    }

    void init();

    return () => {
      cancelled = true;
      cancelAnimationFrame(raf);
      landmarkerRef.current?.close();
      landmarkerRef.current = null;
      cropRef.current = null;
      frameRef.current = null;
      stream?.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
      if (videoRef.current) videoRef.current.srcObject = null;
    };
  }, [enabled, withAudio, withTracking]);

  return { ready, error, frame, frameRef, videoRef, cropRef, streamRef };
}
