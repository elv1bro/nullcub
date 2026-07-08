import { describe, expect, it, vi, afterEach } from "vitest";
import { pollGamepadAbilityEdges, readGamepadMove } from "./gamepad";

function mockPad(partial: {
  axes?: number[];
  buttons?: Array<{ pressed: boolean } | undefined>;
}) {
  return {
    axes: partial.axes ?? [0, 0],
    buttons: partial.buttons ?? [],
  } as Gamepad;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("gamepad", () => {
  it("maps left stick into game move space", () => {
    vi.stubGlobal("navigator", {
      getGamepads: () => [mockPad({ axes: [-0.8, 0.5] })],
    });
    // stick left (−x) → game +x; stick down (+y) → game −y
    expect(readGamepadMove(0)).toEqual({ x: 0.8, y: -0.5 });
  });

  it("ignores stick inside deadzone", () => {
    vi.stubGlobal("navigator", {
      getGamepads: () => [mockPad({ axes: [0.1, -0.1] })],
    });
    expect(readGamepadMove(0)).toEqual({ x: 0, y: 0 });
  });

  it("edge-detects face buttons once", () => {
    const prev: boolean[] = [];
    const buttons = [
      { pressed: true },
      { pressed: false },
      { pressed: false },
      { pressed: false },
    ];
    vi.stubGlobal("navigator", {
      getGamepads: () => [mockPad({ buttons })],
    });
    expect(pollGamepadAbilityEdges(prev, 0).flip).toBe(true);
    expect(pollGamepadAbilityEdges(prev, 0).flip).toBe(false);
  });
});
