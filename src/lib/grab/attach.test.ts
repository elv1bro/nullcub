import { describe, expect, it } from "vitest";
import Matter from "matter-js";
import {
  buildCompositeBodyMap,
  resolveGrabTarget,
} from "./attach";
import { tagStickmanHands } from "./hands";
import { createStickman } from "@/utils/createStickman";

describe("resolveGrabTarget", () => {
  it("rejects grabbing own body segments", () => {
    const stickman = createStickman(100, 100);
    tagStickmanHands(stickman, "player");
    const map = buildCompositeBodyMap([stickman]);
    const hand = stickman.bodies.find(
      (b) => (b.plugin as { part?: string }).part === "handL",
    )!;
    const chest = stickman.bodies.find((b) => b.label === "Chest")!;

    expect(resolveGrabTarget(hand, chest, map)).toBeNull();
  });

  it("allows grabbing opponent body", () => {
    const player = createStickman(100, 100);
    const opponent = createStickman(300, 100);
    tagStickmanHands(player, "player");
    tagStickmanHands(opponent, "opponent");
    const map = buildCompositeBodyMap([player, opponent]);
    const hand = player.bodies.find(
      (b) => (b.plugin as { part?: string }).part === "handR",
    )!;
    const oppHead = opponent.bodies.find((b) => b.label === "Head")!;

    const target = resolveGrabTarget(hand, oppHead, map);
    expect(target?.kind).toBe("fighter");
    expect(target?.compositeId).toBe(opponent.id);
  });

  it("allows grabbing static wall", () => {
    const player = createStickman(100, 100);
    tagStickmanHands(player, "player");
    const wall = Matter.Bodies.rectangle(0, 0, 100, 100, { isStatic: true });
    const map = buildCompositeBodyMap([player]);
    const hand = player.bodies.find(
      (b) => (b.plugin as { part?: string }).part === "handL",
    )!;

    expect(resolveGrabTarget(hand, wall, map)?.kind).toBe("wall");
  });
});
