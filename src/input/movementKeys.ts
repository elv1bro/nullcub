import { useBindingPressRef } from "@/input/keyBindings";
import { readGamepadMove } from "@/input/gamepad";
import type { ControlBindings } from "@/settings/SettingsContext";
import { Vector } from "matter-js";
import type { RefObject } from "react";

export type ExternalMoveRef = RefObject<{ x: number; y: number } | null | undefined>;

/**
 * Движение: только клавиши из `controls` (+ опционально геймпад / тач-стик).
 * Стрелки НЕ дублируют WASD по умолчанию — иначе в локальном 2P
 * стрелки двигают сразу обоих (P2 ими ходит, P1 получает их как alias).
 */
export function useMovementVectorRef(
  controls: ControlBindings,
  opts?: {
    includeArrows?: boolean;
    gamepadIndex?: number | null;
    /** Виртуальный стик / внешний вектор (left=+x, up=+y). */
    externalMoveRef?: ExternalMoveRef;
  },
) {
  const includeArrows = opts?.includeArrows === true;
  const gamepadIndex = opts?.gamepadIndex ?? null;
  const externalMoveRef = opts?.externalMoveRef;
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
    const touch = externalMoveRef?.current;
    if (touch && (touch.x !== 0 || touch.y !== 0)) {
      // Тач-стик перекрывает клавиши/геймпад, пока палец на паде.
      vector = Vector.create(touch.x, touch.y);
    }
    return vector;
  };
}
