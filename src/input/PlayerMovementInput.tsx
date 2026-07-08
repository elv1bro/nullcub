import { useMovementVectorRef } from "@/input/movementKeys";
import { useSettings } from "@/settings/SettingsContext";
import { useEventBeforeUpdate } from "@1.framework/matter4react";
import { Engine, type IEventTimestamped } from "matter-js";
import type { Vector } from "matter-js";

type Props = {
  map: string;
  event: string;
  call: (event: IEventTimestamped<Engine>, vector: Vector) => void;
};

/** Движение: клавиши из настроек + стрелки. */
export function PlayerMovementInput({ map, event, call }: Props) {
  const { settings } = useSettings();
  const readMovement = useMovementVectorRef(settings.controls);

  useEventBeforeUpdate(
    (engineEvent) => {
      const vector = readMovement();
      if (vector.x !== 0 || vector.y !== 0) {
        call(engineEvent, vector);
      }
    },
    [
      map,
      event,
      call,
      settings.controls.up,
      settings.controls.down,
      settings.controls.left,
      settings.controls.right,
    ],
  );

  return null;
}

export { formatBindingLabel as formatKeyLabel } from "@/input/keyBindings";

export const ARROW_ALIASES = {
  up: ["ArrowUp"],
  down: ["ArrowDown"],
  left: ["ArrowLeft"],
  right: ["ArrowRight"],
} as const;
