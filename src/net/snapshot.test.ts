import { describe, expect, it } from "vitest";
import Matter, { Body } from "matter-js";
import { buildItem } from "@/items/buildItem";
import { items } from "@/items/registry";
import "@/items/index";
import { decodeSnapshot, encodeSnapshot } from "./snapshot";

describe("snapshot codec", () => {
  it("roundtrips body positions", () => {
    const composite = buildItem(items.get("frying-pan"), 50, 60);
    const engine = Matter.Engine.create();
    Matter.World.add(engine.world, composite);

    const before = composite.bodies[1]!;
    const origX = before.position.x;
    const origY = before.position.y;

    const encoded = encodeSnapshot([composite]);
    Body.setPosition(before, { x: 500, y: 500 });

    decodeSnapshot(encoded, engine.world, 1);
    expect(before.position.x).toBeCloseTo(origX, 1);
    expect(before.position.y).toBeCloseTo(origY, 1);
  });
});
