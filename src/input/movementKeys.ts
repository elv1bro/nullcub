import { useBindingPressRef } from "@/input/keyBindings";
import { readGamepadMove } from "@/input/gamepad";
import type { ControlBindings } from "@/settings/SettingsContext";
import { Vector } from "matter-js";

/** Движение: клавиши из настроек; стрелки опционально; геймпад (index) опционально. */
export function useMovementVectorRef(
  controls: ControlBindings,
  opts?: { includeArrows?: boolean; gamepadIndex?: number | null },
) {
  const includeArrows = opts?.includeArrows !== false;
  const gamepadIndex = opts?.gamepadIndex ?? null;
  const up = useBindingPressRef(controls.up);
  const down = useBindingPressRef(controls.down);
  const left = useBindingPressRef(controls.left);
  const right = useBindingPressRef(controls.right);

  const arrowUp = useBindingPressRef("ArrowUp");
  const arrowDown = useBindingPressRef("ArrowDown");
  const arrowLeft = useBindingPressRef("ArrowLeft");
  const arrowRight = useBindingPressRef("ArrowRight");

  return () => {
    let vector = Vector.create();
    if (up.current || (includeArrows && arrowUp.current)) {
      vector = Vector.add(vector, { x: 0, y: 1 });
    }
    if (down.current || (includeArrows && arrowDown.current)) {
      vector = Vector.add(vector, { x: 0, y: -1 });
    }
    if (left.current || (includeArrows && arrowLeft.current)) {
      vector = Vector.add(vector, { x: 1, y: 0 });
    }
    if (right.current || (includeArrows && arrowRight.current)) {
      vector = Vector.add(vector, { x: -1, y: 0 });
    }
    if (gamepadIndex != null) {
      const pad = readGamepadMove(gamepadIndex);
      if (pad.x !== 0 || pad.y !== 0) {
        // Геймпад перекрывает клавиши, если стик/D-pad активен.
        vector = Vector.create(pad.x, pad.y);
      }
    }
    return vector;
  };
}
