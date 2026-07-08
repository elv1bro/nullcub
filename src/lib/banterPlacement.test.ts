import { describe, expect, it } from "vitest";
import Matter from "matter-js";
import { findBanterSpot } from "./banterPlacement";

const bounds = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: 1000, y: 1000 },
]);

describe("findBanterSpot", () => {
  it("places banter away from a body at the head", () => {
    const head = Matter.Bodies.circle(300, 400, 20, { isStatic: true });
    const chest = Matter.Bodies.circle(300, 440, 14, { isStatic: true });
    const spot = findBanterSpot(
      head.position.x,
      head.position.y,
      "player",
      "Привет!",
      bounds,
      [head, chest],
      [],
    );

    const distHead = Math.hypot(
      spot.x - head.position.x,
      spot.y - head.position.y,
    );
    expect(distHead).toBeGreaterThan(30);
    expect(spot.y).toBeLessThan(head.position.y + 10);
  });

  it("avoids overlapping existing quips", () => {
    const head = Matter.Bodies.circle(500, 500, 20, { isStatic: true });
    const existing = [
      {
        text: "Уже тут",
        x: 500,
        y: 430,
        born: 0,
        side: "opponent" as const,
        color: "#fff",
        secondary: "#000",
        vx: 0,
        vy: 0,
        rotation: 0,
        spin: 0,
        scale: 1,
      },
    ];
    const spot = findBanterSpot(
      head.position.x,
      head.position.y,
      "opponent",
      "Новая фраза",
      bounds,
      [head],
      existing,
    );

    expect(Math.hypot(spot.x - 500, spot.y - 430)).toBeGreaterThan(45);
  });
});
