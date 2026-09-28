import Matter, { Body } from "matter-js";
import { describe, expect, it } from "vitest";
import {
  FightTape,
  REPLAY_POST_KO_MS,
  applyFightTapePoses,
  findExcitementPeaks,
  lerpAngle,
  speedFromExcitement,
} from "./fightTape";

describe("FightTape", () => {
  it("records poses and excitement spikes on hits", () => {
    const tape = new FightTape();
    const a = Matter.Bodies.circle(10, 20, 5);
    const b = Matter.Bodies.circle(30, 40, 5);
    tape.begin(1000, 2, 100, 100);

    tape.maybeSample(1000, [a, b], { player: 100, opponent: 100 });
    tape.noteHit(120, {
      x: 15,
      y: 25,
      victimSide: "opponent",
      now: 1030,
      playerHp: 100,
      opponentHp: 70,
    });
    tape.maybeSample(1060, [a, b], { player: 100, opponent: 70 });
    tape.noteKo({
      x: 20,
      y: 30,
      victimSide: "opponent",
      now: 1100,
      playerHp: 100,
      opponentHp: 0,
    });
    tape.maybeSample(1120, [a, b], { player: 100, opponent: 0 });
    tape.freeze();

    expect(tape.frameCount).toBeGreaterThanOrEqual(3);
    const wave = tape.waveSamples(16);
    expect(Math.max(...wave)).toBeGreaterThan(0.5);
    expect(tape.durationMs).toBeGreaterThan(0);
    expect(tape.eventsBetween(0, 200).length).toBeGreaterThanOrEqual(2);
    expect(tape.hpAt(0).opponentHp).toBe(100);
    expect(tape.hpAt(40).opponentHp).toBe(70);
    expect(tape.hpAt(200).opponentHp).toBe(0);
    // KO at ~100ms → повтор кончается через REPLAY_POST_KO_MS
    expect(tape.knockoutAtMs).toBeGreaterThanOrEqual(90);
    expect(tape.playbackEndMs).toBeLessThanOrEqual(
      (tape.knockoutAtMs ?? 0) + REPLAY_POST_KO_MS,
    );
  });

  it("playbackEndMs is KO + 5s even if tape is longer", () => {
    const tape = new FightTape();
    const body = Matter.Bodies.circle(0, 0, 5);
    tape.begin(0, 1, 100, 100);
    tape.maybeSample(0, [body], { player: 100, opponent: 100 });
    tape.noteKo({
      x: 0,
      y: 0,
      victimSide: "opponent",
      now: 1000,
      playerHp: 40,
      opponentHp: 0,
    });
    // «длинный» хвост на ленте
    tape.maybeSample(1000 + REPLAY_POST_KO_MS + 3000, [body], {
      player: 40,
      opponent: 0,
    });
    tape.freeze();
    expect(tape.playbackEndMs).toBe(1000 + REPLAY_POST_KO_MS);
    expect(tape.playbackEndMs).toBeLessThan(tape.durationMs);
  });

  it("maps excitement to cinematic cruise / slow-mo (not x8 idle)", () => {
    expect(speedFromExcitement(0)).toBeLessThanOrEqual(3.2);
    expect(speedFromExcitement(0)).toBeGreaterThan(2);
    expect(speedFromExcitement(1)).toBeLessThan(0.4);
    expect(speedFromExcitement(0.2)).toBeGreaterThan(speedFromExcitement(0.8));
  });

  it("interpolates poses between samples for smooth slow-mo", () => {
    const tape = new FightTape();
    const body = Matter.Bodies.circle(0, 0, 5);
    tape.begin(0, 1);
    Body.setPosition(body, { x: 0, y: 0 });
    Body.setAngle(body, 0);
    tape.maybeSample(0, [body]);
    Body.setPosition(body, { x: 100, y: 50 });
    Body.setAngle(body, 1.2);
    tape.maybeSample(100, [body]);
    const out = new Float32Array(3);
    tape.samplePosesAt(50, out);
    expect(out[0]).toBeCloseTo(50, 0);
    expect(out[1]).toBeCloseTo(25, 0);
    expect(out[2]).toBeCloseTo(0.6, 1);
  });

  it("lerpAngle takes shortest path", () => {
    const mid = lerpAngle(2.8, -2.8, 0.5);
    // Кратчайший путь через ±π, не через 0.
    expect(Math.abs(mid)).toBeGreaterThan(2.5);
  });

  it("applies poses back onto bodies", () => {
    const body = Matter.Bodies.circle(0, 0, 5);
    const poses = new Float32Array([100, 200, 0.5]);
    applyFightTapePoses([body], poses);
    expect(body.position.x).toBeCloseTo(100);
    expect(body.position.y).toBeCloseTo(200);
    expect(body.angle).toBeCloseTo(0.5);
    expect(body.velocity.x).toBe(0);
  });

  it("finds peaks on a youtube-like wave", () => {
    const wave = [0.1, 0.2, 0.9, 0.3, 0.2, 0.8, 0.1];
    expect(findExcitementPeaks(wave, 0.5)).toEqual([2, 5]);
  });

  it("indexAtTime finds nearest frame", () => {
    const tape = new FightTape();
    const body = Matter.Bodies.circle(0, 0, 5);
    tape.begin(0, 1);
    Body.setPosition(body, { x: 1, y: 1 });
    tape.maybeSample(0, [body]);
    Body.setPosition(body, { x: 2, y: 2 });
    tape.maybeSample(100, [body]);
    Body.setPosition(body, { x: 3, y: 3 });
    tape.maybeSample(200, [body]);
    expect(tape.indexAtTime(90)).toBe(1);
  });
});
