export type EmotionId =
  | "neutral"
  | "angry"
  | "smile"
  | "scared"
  | "surprised"
  | "pain";

export type Blendshapes = Record<string, number>;

export interface FaceState {
  blendshapes: Blendshapes;
  emotion: EmotionId;
  intensity: number;
}

const NEUTRAL: FaceState = {
  blendshapes: {},
  emotion: "neutral",
  intensity: 0,
};

function score(blendshapes: Blendshapes, keys: string[]): number {
  return keys.reduce((sum, key) => sum + (blendshapes[key] ?? 0), 0);
}

/** Классификация эмоции по blendshapes MediaPipe. */
export function detectEmotion(
  blendshapes: Blendshapes,
  forced?: EmotionId,
): FaceState {
  if (forced) {
    return { blendshapes, emotion: forced, intensity: 1 };
  }

  const candidates: Array<[EmotionId, number]> = [
    [
      "angry",
      score(blendshapes, ["browDownLeft", "browDownRight", "jawOpen"]) * 0.5 +
        score(blendshapes, ["mouthFrownLeft", "mouthFrownRight"]),
    ],
    [
      "smile",
      score(blendshapes, ["mouthSmileLeft", "mouthSmileRight", "cheekSquintLeft", "cheekSquintRight"]),
    ],
    [
      "scared",
      score(blendshapes, ["eyeWideLeft", "eyeWideRight", "browInnerUp", "jawOpen"]),
    ],
    [
      "surprised",
      score(blendshapes, ["jawOpen", "eyeWideLeft", "eyeWideRight", "browOuterUpLeft", "browOuterUpRight"]),
    ],
  ];

  const [emotion, intensity] = candidates.reduce(
    (best, current) => (current[1] > best[1] ? current : best),
    ["neutral", 0] as [EmotionId, number],
  );

  if (intensity < 0.35) return NEUTRAL;
  return { blendshapes, emotion, intensity: Math.min(1, intensity) };
}

/** Автономная морда бота: злится, когда здоров; корчится от боли после удара. */
export function botEmotion(
  hp: number,
  maxHp: number,
  painFlash: boolean,
): FaceState {
  if (painFlash) return detectEmotion({}, "pain");
  if (hp / maxHp < 0.35) return detectEmotion({}, "scared");
  return detectEmotion({}, "angry");
}
