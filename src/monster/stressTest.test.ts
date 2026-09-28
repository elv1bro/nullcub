import { describe, expect, it } from "vitest";
import { stressTestMonsterDef } from "./workshopIntegrity";
import { normalizeMonsterDef } from "./monsterTypes";

describe("stressTestMonsterDef", () => {
  it("passes default workshop head+core rigid", () => {
    const result = stressTestMonsterDef(
      normalizeMonsterDef({
        id: "t",
        name: "T",
        parts: [
          { x: 0, y: -40, radius: 20, isHead: true },
          { x: 0, y: 20, radius: 12, isHead: false },
        ],
        links: [{ a: 0, b: 1, type: "rigid" }],
        createdAt: 0,
      }),
      60,
    );
    expect(result.ok, result.broken.join(", ")).toBe(true);
  });
});
