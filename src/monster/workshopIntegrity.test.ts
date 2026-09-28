import { describe, expect, it } from "vitest";
import {
  runMonsterIntegrityFight,
  runStarterIntegritySuite,
} from "./workshopIntegrity";
import { normalizeMonsterDef } from "./monsterTypes";

describe("workshop:integrity", () => {
  it("all starter monsters stay assembled under hard AI", () => {
    const results = runStarterIntegritySuite(300);
    const failed = results.filter((r) => !r.ok);
    expect(
      failed,
      failed.map((f) => `${f.name}: ${f.broken.join(", ")}`).join(" | "),
    ).toEqual([]);
  });

  it("mixed spring/rope custom stays assembled", () => {
    const result = runMonsterIntegrityFight(
      normalizeMonsterDef({
        id: "mixed",
        name: "Mixed",
        parts: [
          { x: 0, y: -28, radius: 20, isHead: true },
          { x: 0, y: 8, radius: 14, isHead: false },
          { x: -24, y: 36, radius: 12, isHead: false },
          { x: 24, y: 36, radius: 12, isHead: false },
        ],
        links: [
          { a: 0, b: 1, type: "rigid" },
          { a: 1, b: 2, type: "spring" },
          { a: 1, b: 3, type: "rope" },
        ],
        createdAt: 0,
      }),
      300,
    );
    expect(result.ok, result.broken.join(", ")).toBe(true);
  });
});
