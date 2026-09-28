import { describe, expect, it } from "vitest";
import { generateRoguelikeMap, getPortal } from "./map";

describe("roguelike map", () => {
  it("builds all floors ahead with 3 directional exits", () => {
    const map = generateRoguelikeMap({
      floorsTotal: 5,
      difficulty: "normal",
      seed: 42,
      playerCount: 2,
    });
    expect(map.floors).toHaveLength(5);
    for (const floor of map.floors) {
      expect(floor.portals).toHaveLength(3);
      expect(floor.portals.map((p) => p.direction)).toEqual([
        "left",
        "forward",
        "right",
      ]);
      for (const p of floor.portals) {
        expect(p.face).toBe("east");
        expect(p.lootPreview.length).toBeGreaterThan(0);
        expect(p.rewardPool.length).toBeGreaterThanOrEqual(p.lootPreview.length);
      }
    }
    // Детерминизм по seed
    const map2 = generateRoguelikeMap({
      floorsTotal: 5,
      difficulty: "normal",
      seed: 42,
      playerCount: 2,
    });
    expect(map2.floors[0]!.portals[0]!.lootPreview).toEqual(
      map.floors[0]!.portals[0]!.lootPreview,
    );
  });

  it("finds portal by id", () => {
    const map = generateRoguelikeMap({ seed: 7 });
    const id = map.floors[0]!.portals[0]!.id;
    expect(getPortal(map, id)?.portal.id).toBe(id);
  });
});
