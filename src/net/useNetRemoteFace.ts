import type { FaceCropRect } from "@/face/faceCrop";
import type { FaceState } from "@/face/emotions";
import { useNetSession } from "./NetSessionContext";
import { useEffect, useRef, useState } from "react";
import type { FacePrivacyMode } from "./protocol";

const NEUTRAL_FACE: FaceState = {
  blendshapes: {},
  emotion: "neutral",
  intensity: 0,
};

/** Приём crop/emotion/stream первого пира для отрисовки на голове оппонента. */
export function useNetRemoteFace(enabled: boolean) {
  const net = useNetSession();
  const [face, setFace] = useState<FaceState>(NEUTRAL_FACE);
  const cropRef = useRef<FaceCropRect | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [webcamActive, setWebcamActive] = useState(false);
  const [faceMode, setFaceMode] = useState<FacePrivacyMode>("video");

  useEffect(() => {
    if (!enabled) return;
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.autoplay = true;
    videoRef.current = video;
    return () => {
      video.srcObject = null;
      videoRef.current = null;
    };
  }, [enabled]);

  useEffect(() => {
    if (!enabled || !net.actions) return;
    const [, onEmotion] = net.actions.emotion;
    const [, onCrop] = net.actions.crop;
    const [, onMedia] = net.actions.mediaState;

    onEmotion((data) => {
      setFace({
        blendshapes: {},
        emotion: data.emotion as FaceState["emotion"],
        intensity: data.intensity,
      });
    });

    onCrop((data) => {
      cropRef.current = {
        sx: data.x,
        sy: data.y,
        sw: data.w,
        sh: data.h,
      };
    });

    onMedia((data) => {
      setFaceMode(data.faceMode);
      setWebcamActive(data.cam && data.faceMode === "video");
    });
  }, [enabled, net.actions]);

  useEffect(() => {
    const video = videoRef.current;
    const peer = net.peers[0];
    if (!enabled || !video || !peer?.stream) return;
    if (peer.faceMode !== "video" || !peer.cam) {
      video.srcObject = null;
      return;
    }
    video.srcObject = peer.stream;
    void video.play().catch(() => {});
  }, [enabled, net.peers]);

  return {
    face,
    cropRef,
    videoRef,
    webcamActive: webcamActive && faceMode === "video",
    faceMode,
    peerName: net.peers[0]?.name ?? "",
  };
}
