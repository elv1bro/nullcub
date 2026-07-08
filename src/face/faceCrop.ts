/** Область кадра вебки (пиксели видео) для drawImage. */
export interface FaceCropRect {
  sx: number;
  sy: number;
  sw: number;
  sh: number;
}

export interface NormalizedPoint {
  x: number;
  y: number;
}

/** Bbox лица из landmarks MediaPipe → квадратный кроп с полями. */
export function landmarksToCrop(
  landmarks: NormalizedPoint[],
  videoWidth: number,
  videoHeight: number,
  padding = 1.55,
): FaceCropRect | null {
  if (landmarks.length === 0 || videoWidth <= 0 || videoHeight <= 0) return null;

  let minX = 1;
  let minY = 1;
  let maxX = 0;
  let maxY = 0;
  for (const lm of landmarks) {
    minX = Math.min(minX, lm.x);
    minY = Math.min(minY, lm.y);
    maxX = Math.max(maxX, lm.x);
    maxY = Math.max(maxY, lm.y);
  }

  const faceW = (maxX - minX) * videoWidth;
  const faceH = (maxY - minY) * videoHeight;
  if (faceW < 8 || faceH < 8) return null;

  // Чуть выше центра — чтобы влезли лоб и подбородок в круг
  const cx = ((minX + maxX) / 2) * videoWidth;
  const cy = ((minY + maxY) / 2 - (maxY - minY) * 0.06) * videoHeight;
  const size = Math.max(faceW, faceH) * padding;

  let sx = cx - size / 2;
  let sy = cy - size / 2;

  // Удерживаем квадрат внутри кадра
  if (size > videoWidth) {
    sx = 0;
  } else {
    sx = Math.max(0, Math.min(videoWidth - size, sx));
  }
  if (size > videoHeight) {
    sy = 0;
  } else {
    sy = Math.max(0, Math.min(videoHeight - size, sy));
  }

  const sw = Math.min(size, videoWidth - sx);
  const sh = Math.min(size, videoHeight - sy);
  if (sw < 8 || sh < 8) return null;

  return { sx, sy, sw, sh };
}

/** Центральный квадрат — запасной кроп без детекции. */
export function centerCrop(videoWidth: number, videoHeight: number): FaceCropRect {
  const side = Math.min(videoWidth, videoHeight);
  return {
    sx: (videoWidth - side) / 2,
    sy: (videoHeight - side) / 2,
    sw: side,
    sh: side,
  };
}

const SMOOTH = 0.28;

export function smoothCrop(
  prev: FaceCropRect | null,
  next: FaceCropRect,
): FaceCropRect {
  if (!prev) return next;
  const lerp = (a: number, b: number) => a + (b - a) * SMOOTH;
  return {
    sx: lerp(prev.sx, next.sx),
    sy: lerp(prev.sy, next.sy),
    sw: lerp(prev.sw, next.sw),
    sh: lerp(prev.sh, next.sh),
  };
}
