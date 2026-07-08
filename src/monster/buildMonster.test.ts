import { describe, expect, it } from "vitest";
import { buildMonster } from "./buildMonster";
import type { MonsterDef } from "./monsterTypes";
import { monsterMaxHp } from "./monsterTypes";

const sample: MonsterDef = {
  id: "test-monster",
  name: "Test",
  parts: [
    { x: 0, y: -20, radius: 20, isHead: true },
    { x: 0, y: 20, radius: 12, isHead: false },
    { x: 30, y: 20, radius: 10, isHead: false },
  ],
  links: [
    { a: 0, b: 1 },
    { a: 1, b: 2 },
  ],
  createdAt: 0,
};

describe("buildMonster", () => {
  it("creates composite with head label and constraints", () => {
    const built = buildMonster(sample, 500, 500);
    expect(built).not.toBeNull();
    expect(built!.composite.bodies.length).toBe(3);
    expect(built!.head?.label).toBe("Head");
    expect(built!.composite.constraints.length).toBe(4);
    expect(built!.maxHp).toBe(monsterMaxHp(3));
  });

  it("marks armor parts without damage label", () => {
    const withArmor: MonsterDef = {
      ...sample,
      parts: [
        { x: 0, y: -20, radius: 20, isHead: true },
        { x: 0, y: 20, radius: 12, isHead: false, role: "armor" },
      ],
      links: [{ a: 0, b: 1 }],
    };
    const built = buildMonster(withArmor, 500, 500);
    expect(built!.composite.bodies[1]?.label).toBe("Armor");
  });

  it("returns null for empty monster", () => {
    expect(buildMonster({ ...sample, parts: [], links: [] }, 0, 0)).toBeNull();
  });
});

describe("monsterMaxHp", () => {
  it("scales with part count", () => {
    expect(monsterMaxHp(1)).toBe(40);
    expect(monsterMaxHp(5)).toBe(200);
  });
});
