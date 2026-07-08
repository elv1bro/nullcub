import { describe, expect, it } from "vitest";
import Matter, { Body } from "matter-js";
import { createStickman } from "@/utils/createStickman";
import {
  decodeBodiesOrdered,
  encodeBodiesOrdered,
} from "./snapshot";

describe("ordered snapshot codec", () => {
  it("applies poses by index even when body.id differs", () => {
    const host = createStickman(100, 200, { render: { visible: false } });
    const guest = createStickman(100, 200, { render: { visible: false } });

    // Сдвигаем хоста
    for (const body of host.bodies) {
      Body.setPosition(body, {
        x: body.position.x + 40,
        y: body.position.y - 10,
      });
    }

    const encoded = encodeBodiesOrdered(host.bodies);
    decodeBodiesOrdered(encoded, guest.bodies, 1);

    for (let i = 0; i < host.bodies.length; i++) {
      expect(guest.bodies[i]!.position.x).toBeCloseTo(
        host.bodies[i]!.position.x,
        4,
      );
      expect(guest.bodies[i]!.position.y).toBeCloseTo(
        host.bodies[i]!.position.y,
        4,
      );
    }

    // id могут отличаться — это ок для ordered codec
    expect(host.bodies[0]!.id).not.toBe(guest.bodies[0]!.id);
    Matter.Composite.clear(host, false);
    Matter.Composite.clear(guest, false);
  });
});
