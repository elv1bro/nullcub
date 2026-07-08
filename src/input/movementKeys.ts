import { useBindingPressRef } from "@/input/keyBindings";
import type { ControlBindings } from "@/settings/SettingsContext";
import { Vector } from "matter-js";

/** Движение: клавиши из настроек; стрелки опционально (одиночная игра). */
export function useMovementVectorRef(
  controls: ControlBindings,
  opts?: { includeArrows?: boolean },
) {
  const includeArrows = opts?.includeArrows !== false;
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
    return vector;
  };
}
