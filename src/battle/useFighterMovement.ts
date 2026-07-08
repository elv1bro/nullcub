import { useMovementVectorRef } from "@/input/movementKeys";
import { PLAYER_MOVE_SPEED } from "@/lib/battleTuning";
import { moveBody } from "@/lib/moveBody";
import {
  DEFAULT_CONTROLS,
  DEFAULT_CONTROLS_P2,
  useSettings,
} from "@/settings/SettingsContext";
import { useEventBeforeUpdate } from "@1.framework/matter4react";
import Matter, { type Body, type IEventTimestamped } from "matter-js";
import type { MutableRefObject } from "react";

export type MovementController = "keyboard" | "keyboard2" | "none";

export function useFighterMovement(
  headRef: MutableRefObject<Body | undefined>,
  controller: MovementController,
  disabledRef?: MutableRefObject<boolean>,
  speedMultRef?: MutableRefObject<number>,
  inputBlockedRef?: MutableRefObject<boolean>,
): void {
  const { settings } = useSettings();
  const readP1 = useMovementVectorRef(settings.controls ?? DEFAULT_CONTROLS, {
    includeArrows: false,
  });
  const readP2 = useMovementVectorRef(settings.controlsP2 ?? DEFAULT_CONTROLS_P2, {
    includeArrows: false,
  });

  useEventBeforeUpdate(
    (event: IEventTimestamped<Matter.Engine>) => {
      if (disabledRef?.current || inputBlockedRef?.current) return;
      if (controller === "none") return;
      const head = headRef.current;
      if (!head) return;
      const vector = controller === "keyboard2" ? readP2() : readP1();
      if (vector.x === 0 && vector.y === 0) return;
      const speed = PLAYER_MOVE_SPEED * (speedMultRef?.current ?? 1);
      moveBody(head)(event, vector, speed);
    },
    [headRef, controller, disabledRef, speedMultRef, inputBlockedRef, readP1, readP2],
  );
}
