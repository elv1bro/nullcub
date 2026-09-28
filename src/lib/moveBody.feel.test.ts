import Matter from "matter-js";
import { describe, expect, it } from "vitest";
import { PLAYER_MOVE_SPEED } from "./battleTuning";
import { moveBody, toMoveInput } from "./moveBody";

describe("movement clarity", () => {
  it("player head closes a 140px gap in under 3 seconds at walk speed", () => {
    const engine = Matter.Engine.create({
      gravity: { x: 0, y: 0, scale: 0 },
    });
    const head = Matter.Bodies.circle(360, 500, 20, {
      frictionAir: 0.02,
    });
    Matter.World.add(engine.world, head);

    const targetX = 500;
    const fakeEvent = { delta: 1000 / 60 } as unknown as Matter.IEventTimestamped<Matter.Engine>;
    const apply = moveBody(head);
    let frames = 0;
    const maxFrames = 180; // 3s

    while (frames < maxFrames && head.position.x < targetX - 8) {
      apply(fakeEvent, toMoveInput({ x: 1, y: 0 }), PLAYER_MOVE_SPEED);
      Matter.Engine.update(engine, 1000 / 60);
      frames++;
    }

    expect(head.position.x).toBeGreaterThan(targetX - 12);
    expect(frames / 60).toBeLessThan(3);
    Matter.Engine.clear(engine);
  });
});
