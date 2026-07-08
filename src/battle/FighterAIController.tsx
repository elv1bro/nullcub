import { useAIMoves } from "@/lib/useAIMoves";
import type { AiProfile } from "@/battle/aiProfiles";
import type { Bounds, Body, Composite } from "matter-js";
import type { MutableRefObject } from "react";

export function FighterAIController({
  headRef,
  targetRef,
  disabledRef,
  bounds,
  speedMult = 1,
  profile = null,
  compositeRef,
  grabLeftRef,
  grabRightRef,
}: {
  headRef: MutableRefObject<Body | undefined>;
  targetRef: MutableRefObject<Body | undefined>;
  disabledRef: MutableRefObject<boolean>;
  bounds: Bounds;
  speedMult?: number;
  profile?: AiProfile | null;
  compositeRef?: MutableRefObject<Composite | undefined>;
  grabLeftRef?: MutableRefObject<boolean>;
  grabRightRef?: MutableRefObject<boolean>;
}) {
  const speedRef = { current: speedMult };
  speedRef.current = speedMult;
  useAIMoves(
    headRef,
    targetRef,
    disabledRef,
    bounds,
    speedRef,
    profile,
    grabLeftRef,
    grabRightRef,
    compositeRef,
  );
  return null;
}
