import { useBotAI } from "@/battle/useBotAI";
import { getAiProfile, type AiDifficultyId, type AiProfile } from "@/battle/aiProfiles";
import type { Bounds, Body } from "matter-js";
import type { MutableRefObject } from "react";
import debug from "debug";

export const log = debug("@:lib:useAIMoves");

function legacyProfileFromSpeed(mult: number): AiProfile {
  let id: AiDifficultyId = "normal";
  if (mult <= 0.8) id = "easy";
  else if (mult >= 1.25) id = "boss";
  else if (mult >= 1.1) id = "hard";
  return { ...getAiProfile(id), speedMult: mult };
}

export function useAIMoves(
  headRef: MutableRefObject<Body | undefined>,
  playerRef: MutableRefObject<Body | undefined>,
  disabledRef?: MutableRefObject<boolean>,
  bounds?: Bounds,
  speedMultRef?: MutableRefObject<number>,
  profile?: AiProfile | null,
  grabLeftRef?: MutableRefObject<boolean>,
  grabRightRef?: MutableRefObject<boolean>,
  botCompositeRef?: MutableRefObject<import("matter-js").Composite | undefined>,
): void {
  const fallback = legacyProfileFromSpeed(speedMultRef?.current ?? 1);

  useBotAI({
    profile: profile ?? fallback,
    botHeadRef: headRef,
    playerHeadRef: playerRef,
    botCompositeRef,
    disabledRef,
    bounds,
    grabLeftRef,
    grabRightRef,
    speedMultOverrideRef: profile ? speedMultRef : undefined,
  });
}
