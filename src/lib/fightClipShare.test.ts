import { describe, expect, it } from "vitest";
import {
  decodeFightClipShare,
  encodeFightClipShare,
  compactFightClip,
} from "./fightClipShare";
import type { FightTapeClip } from "./fightTape";

function sampleClip(): FightTapeClip {
  return {
    v: 1,
    bodyCount: 2,
    durationMs: 2000,
    times: [0, 100, 200],
    poses: [
      [1, 2, 0, 3, 4, 0],
      [1.1, 2.1, 0.1, 3.1, 4.1, 0],
      [1.2, 2.2, 0.2, 3.2, 4.2, 0],
    ],
    events: [
      {
        t: 100,
        kind: "hit",
        damage: 20,
        x: 10,
        y: 20,
        victimSide: "opponent",
        dirX: 1,
        dirY: 0,
      },
    ],
  };
}

describe("fightClipShare", () => {
  it("roundtrips encode/decode", () => {
    const raw = encodeFightClipShare(sampleClip());
    expect(raw.startsWith("RFR1.")).toBe(true);
    const back = decodeFightClipShare(raw);
    expect(back?.bodyCount).toBe(2);
    expect(back?.events[0]?.damage).toBe(20);
  });

  it("compacts long clips", () => {
    const times = Array.from({ length: 200 }, (_, i) => i * 100);
    const poses = times.map(() => [0, 0, 0, 1, 1, 0]);
    const compact = compactFightClip({
      v: 1,
      bodyCount: 2,
      durationMs: 20_000,
      times,
      poses,
      events: [],
    });
    expect(compact.durationMs).toBeLessThanOrEqual(12_000);
    expect(compact.poses.length).toBeLessThanOrEqual(140);
  });
});
