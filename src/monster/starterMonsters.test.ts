import { describe, expect, it } from "vitest";
import { buildMonster } from "./buildMonster";
import { normalizeMonsterDef } from "./monsterTypes";
import { STARTER_MONSTERS } from "./starterMonsters";

describe("starterMonsters", () => {
  it("every preset builds with a head and at least one hurtbox", () => {
    for (const template of STARTER_MONSTERS) {
      const def = normalizeMonsterDef({
        ...template,
        id: "test",
        createdAt: 0,
      });
      const built = buildMonster(def, 450, 450);
      expect(built, template.name).not.toBeNull();
      expect(built!.head?.label).toBe("Head");
      expect(
        def.parts.some((p) => p.isHead || p.role !== "armor"),
        template.name,
      ).toBe(true);
      expect(built!.composite.constraints.length).toBeGreaterThanOrEqual(
        def.links.length,
      );
    }
  });
});
