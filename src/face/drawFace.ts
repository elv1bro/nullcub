import Matter from "matter-js";
import type { FaceCropRect } from "./faceCrop";
import type { FaceOverlayEffectId } from "./faceEffects";
import { drawFaceOverlayEffect } from "./faceEffects";
import type { EmotionId, FaceState } from "./emotions";
import { worldToCanvas } from "@/render/worldToCanvas";

function headCanvasPos(render: Matter.Render, head: Matter.Body) {
  return worldToCanvas(render, head.position);
}

function eyeOffset(emotion: EmotionId, side: -1 | 1): { x: number; y: number } {
  switch (emotion) {
    case "angry":
      return { x: side * 0.28, y: -0.08 };
    case "scared":
    case "surprised":
      return { x: side * 0.3, y: -0.18 };
    case "pain":
      return { x: side * 0.26, y: -0.05 };
    case "smile":
      return { x: side * 0.28, y: -0.12 };
    default:
      return { x: side * 0.28, y: -0.12 };
  }
}

function drawEye(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  r: number,
  emotion: EmotionId,
): void {
  ctx.fillStyle = "#fff";
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();

  const pupilR = r * 0.45;
  let pupilY = y;
  if (emotion === "scared" || emotion === "surprised") pupilY += r * 0.15;

  ctx.fillStyle = "#111";
  ctx.beginPath();
  ctx.arc(x, pupilY, pupilR, 0, Math.PI * 2);
  ctx.fill();

  if (emotion === "angry") {
    ctx.strokeStyle = "#111";
    ctx.lineWidth = r * 0.22;
    ctx.beginPath();
    ctx.moveTo(x - r * 1.1, y - r * 1.3);
    ctx.lineTo(x + r * 0.9, y - r * 0.5);
    ctx.stroke();
  }
}

function drawMouth(
  ctx: CanvasRenderingContext2D,
  emotion: EmotionId,
  intensity: number,
  blendshapes: Record<string, number>,
  r: number,
): void {
  const smile =
    ((blendshapes.mouthSmileLeft ?? 0) + (blendshapes.mouthSmileRight ?? 0)) / 2;
  const open = blendshapes.jawOpen ?? 0;
  ctx.strokeStyle = "#111";
  ctx.lineWidth = Math.max(1.5, r * 0.12);
  ctx.lineCap = "round";
  ctx.beginPath();

  const y = r * 0.28;
  const w = r * 0.55;

  if (emotion === "pain") {
    ctx.arc(0, y, w * 0.35, 0, Math.PI, false);
  } else if (emotion === "smile" || smile > 0.25) {
    ctx.arc(0, y - r * 0.1 * intensity, w, 0.15 * Math.PI, 0.85 * Math.PI, false);
  } else if (emotion === "scared" || emotion === "surprised" || open > 0.35) {
    ctx.ellipse(0, y, w * 0.35, w * 0.45 * Math.max(intensity, open), 0, 0, Math.PI * 2);
  } else if (emotion === "angry") {
    ctx.moveTo(-w, y);
    ctx.lineTo(w, y);
  } else {
    ctx.moveTo(-w * 0.5, y);
    ctx.lineTo(w * 0.5, y);
  }
  ctx.stroke();
}

export const HEAD_FRAME_PX = 2;
/** Радиус круга лица / вебки относительно r головы. */
export const HEAD_FACE_CLIP = 0.9;

export function drawHeadFrame(
  ctx: CanvasRenderingContext2D,
  edgeRadius: number,
  frameColor: string,
): void {
  ctx.strokeStyle = frameColor;
  ctx.lineWidth = HEAD_FRAME_PX;
  ctx.beginPath();
  ctx.arc(0, 0, edgeRadius, 0, Math.PI * 2);
  ctx.stroke();
}

/** Белая голова-заглушка, если вебка выключена. */
export function drawPlaceholderHead(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  head: Matter.Body,
  _frameColor = "#888888",
  options: {
    faceEffect?: FaceOverlayEffectId;
    now?: number;
  } = {},
): void {
  const radius = head.circleRadius ?? 20;
  const { x, y, scale } = headCanvasPos(render, head);
  const r = radius * scale;

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(head.angle);

  ctx.fillStyle = "#f8f8f8";
  ctx.beginPath();
  ctx.arc(0, 0, r * HEAD_FACE_CLIP, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = "#555";
  ctx.font = `900 ${r * 1.1}px Anton, Impact, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("?", 0, r * 0.05);

  if (options.faceEffect && options.faceEffect !== "none") {
    drawFaceOverlayEffect(ctx, r, options.faceEffect, options.now ?? 0);
  }

  ctx.restore();
}

/** Рамка головы — рисуется последней поверх лица/вебки/эффектов. */
export function drawHeadFrameOnHead(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  head: Matter.Body,
  frameColor: string,
): void {
  const radius = head.circleRadius ?? 20;
  const { x, y, scale } = headCanvasPos(render, head);
  const r = radius * scale;

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(head.angle);
  drawHeadFrame(ctx, r * HEAD_FACE_CLIP, frameColor);
  ctx.restore();
}

/** Рисует кадр вебки в круг головы (зеркально, с автозумом по лицу). */
export function drawWebcamOnHead(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  head: Matter.Body,
  video: HTMLVideoElement,
  options: {
    painFlash?: boolean;
    crop?: FaceCropRect | null;
    frameColor?: string;
    faceEffect?: FaceOverlayEffectId;
    now?: number;
  } = {},
): void {
  if (video.readyState < 2 || video.videoWidth === 0) return;

  const radius = head.circleRadius ?? 20;
  const { x, y, scale } = headCanvasPos(render, head);
  const r = radius * scale;
  const d = r * 2;

  const vw = video.videoWidth;
  const vh = video.videoHeight;
  const crop =
    options.crop ??
    ({
      sx: (vw - Math.min(vw, vh)) / 2,
      sy: (vh - Math.min(vw, vh)) / 2,
      sw: Math.min(vw, vh),
      sh: Math.min(vw, vh),
    } satisfies FaceCropRect);

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(head.angle);

  ctx.beginPath();
  ctx.arc(0, 0, r * HEAD_FACE_CLIP, 0, Math.PI * 2);
  ctx.clip();

  ctx.scale(-1, 1);
  ctx.drawImage(video, crop.sx, crop.sy, crop.sw, crop.sh, -r * HEAD_FACE_CLIP, -r * HEAD_FACE_CLIP, d * HEAD_FACE_CLIP, d * HEAD_FACE_CLIP);

  if (options.painFlash) {
    ctx.scale(-1, 1);
    ctx.fillStyle = "rgba(255, 40, 40, 0.45)";
    ctx.fillRect(-r, -r, d, d);
  }

  ctx.restore();

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(head.angle);
  if (options.faceEffect && options.faceEffect !== "none") {
    ctx.beginPath();
    ctx.arc(0, 0, r * HEAD_FACE_CLIP, 0, Math.PI * 2);
    ctx.clip();
    drawFaceOverlayEffect(ctx, r, options.faceEffect, options.now ?? 0);
  }
  ctx.restore();
}

/** Рисует мультяшную морду поверх круга-головы. */
export function drawFaceOnHead(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  head: Matter.Body,
  face: FaceState,
  frameColor = "#333333",
): void {
  const radius = head.circleRadius ?? 20;
  const { x, y, scale } = headCanvasPos(render, head);
  const r = radius * scale;

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(head.angle);

  // «Лицо» чуть светлее тела
  ctx.fillStyle = "rgba(255, 240, 220, 0.92)";
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.88, 0, Math.PI * 2);
  ctx.fill();

  const left = eyeOffset(face.emotion, -1);
  const right = eyeOffset(face.emotion, 1);
  const eyeR = r * 0.15;
  drawEye(ctx, left.x * r, left.y * r, eyeR, face.emotion);
  drawEye(ctx, right.x * r, right.y * r, eyeR, face.emotion);
  drawMouth(ctx, face.emotion, face.intensity, face.blendshapes, r);

  drawHeadFrame(ctx, r * HEAD_FACE_CLIP, frameColor);

  ctx.restore();
}
