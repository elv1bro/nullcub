/**
 * Чтение геймпада для боя: левый стик → движение, face-кнопки → abilities.
 * Стандартный mapping (Xbox / DualShock через browser Gamepad API).
 */

const DEADZONE = 0.28;

export type GamepadAbilityEdges = {
  dash: boolean;
  flip: boolean;
  freeze: boolean;
  reset: boolean;
};

/** Движение в системе клавиш игры: left=+x, up=+y. */
export function readGamepadMove(index = 0): { x: number; y: number } {
  if (typeof navigator === "undefined" || !navigator.getGamepads) {
    return { x: 0, y: 0 };
  }
  const pad = navigator.getGamepads()[index];
  if (!pad) return { x: 0, y: 0 };

  let ax = pad.axes[0] ?? 0;
  let ay = pad.axes[1] ?? 0;
  if (Math.abs(ax) < DEADZONE) ax = 0;
  if (Math.abs(ay) < DEADZONE) ay = 0;

  // Стик: влево −1 → в игре left = +x; вверх −1 → up = +y.
  let x = ax !== 0 ? -ax : 0;
  let y = ay !== 0 ? -ay : 0;

  // D-pad (кнопки 12–15) как запасной ввод.
  if (pad.buttons[14]?.pressed) x = 1;
  if (pad.buttons[15]?.pressed) x = -1;
  if (pad.buttons[12]?.pressed) y = 1;
  if (pad.buttons[13]?.pressed) y = -1;

  return { x, y };
}

/**
 * Edge-detect face buttons → ability one-shots.
 * 0 A/Cross = flip, 1 B/Circle = dash, 2 X/Square = brace, 3 Y/Triangle = reset.
 */
export function pollGamepadAbilityEdges(
  prevPressed: boolean[],
  index = 0,
): GamepadAbilityEdges {
  const edges: GamepadAbilityEdges = {
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
  };
  if (typeof navigator === "undefined" || !navigator.getGamepads) {
    return edges;
  }
  const pad = navigator.getGamepads()[index];
  if (!pad) return edges;

  const map: Array<[number, keyof GamepadAbilityEdges]> = [
    [0, "flip"],
    [1, "dash"],
    [2, "freeze"],
    [3, "reset"],
  ];
  for (const [btn, key] of map) {
    const down = Boolean(pad.buttons[btn]?.pressed);
    const was = prevPressed[btn] ?? false;
    if (down && !was) edges[key] = true;
    prevPressed[btn] = down;
  }
  return edges;
}
