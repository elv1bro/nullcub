import { useEventBeforeUpdate } from "@1.framework/matter4react";
import { moveBody, toMoveInput } from "@/lib/moveBody";
import {
  type Body,
  type Bounds,
  type Composite,
  type Engine,
  type IEventTimestamped,
} from "matter-js";
import { useRef, type MutableRefObject } from "react";
import type { AiProfile } from "./aiProfiles";
import {
  computeBotMoveIntent,
  createBotBrainState,
  tickBotAbilities,
  type BotBrainState,
} from "./aiLogic";

export function useBotAI(opts: {
  profile: AiProfile | null;
  botHeadRef: MutableRefObject<Body | undefined>;
  playerHeadRef: MutableRefObject<Body | undefined>;
  botCompositeRef?: MutableRefObject<Composite | undefined>;
  disabledRef?: MutableRefObject<boolean>;
  bounds?: Bounds;
  grabLeftRef?: MutableRefObject<boolean>;
  grabRightRef?: MutableRefObject<boolean>;
  /** Legacy: переопределяет speedMult каждый кадр (кампания). */
  speedMultOverrideRef?: MutableRefObject<number>;
}): void {
  const brainRef = useRef<BotBrainState>(createBotBrainState());

  useEventBeforeUpdate(
    (event: IEventTimestamped<Engine>) => {
      if (opts.disabledRef?.current) return;
      let profile = opts.profile;
      if (!profile) return;

      if (opts.speedMultOverrideRef) {
        profile = {
          ...profile,
          speedMult: opts.speedMultOverrideRef.current,
        };
      }

      const botHead = opts.botHeadRef.current;
      const playerHead = opts.playerHeadRef.current;
      if (!(botHead && playerHead)) return;

      const now = performance.now();
      const intent = computeBotMoveIntent(
        profile,
        brainRef.current,
        botHead,
        playerHead,
        opts.bounds,
        now,
      );

      if (opts.grabLeftRef) opts.grabLeftRef.current = intent.grabL;
      if (opts.grabRightRef) opts.grabRightRef.current = intent.grabR;

      tickBotAbilities(
        profile,
        brainRef.current,
        opts.botCompositeRef?.current,
        botHead,
        playerHead,
        now,
      );

      moveBody(botHead)(event, toMoveInput(intent.worldMove), intent.speed);
    },
    [
      opts.profile,
      opts.botHeadRef,
      opts.playerHeadRef,
      opts.botCompositeRef,
      opts.disabledRef,
      opts.bounds,
      opts.grabLeftRef,
      opts.grabRightRef,
      opts.speedMultOverrideRef,
    ],
  );
}
