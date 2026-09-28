import { describe, expect, it } from "vitest";
import { decodeMonsterShare, encodeMonsterShare } from "./monsterShare";
import { normalizeMonsterDef } from "./monsterTypes";

describe("monster share string", () => {
  it("round-trips a connected monster", () => {
    const def = normalizeMonsterDef({
      id: "a",
      name: "Share Me",
      parts: [
        { x: 0, y: -20, radius: 20, isHead: true },
        { x: 0, y: 20, radius: 12, isHead: false },
      ],
      links: [{ a: 0, b: 1, type: "spring" }],
      stats: { maxHp: 180, defense: 8 },
      createdAt: 1,
    });
    const code = encodeMonsterShare(def);
    expect(code.startsWith("RFM1.")).toBe(true);
    const back = decodeMonsterShare(code);
    expect(back).not.toBeNull();
    expect(back!.name).toBe("Share Me");
    expect(back!.parts).toHaveLength(2);
    expect(back!.links[0]?.type).toBe("spring");
    expect(back!.stats?.maxHp).toBe(180);
  });

  it("rejects garbage", () => {
    expect(decodeMonsterShare("not-a-code")).toBeNull();
    expect(decodeMonsterShare("RFM1.!!!")).toBeNull();
  });
});
