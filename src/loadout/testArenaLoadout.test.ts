import { describe, expect, it } from "vitest";
import { buildTestArenaLoadout } from "./testArenaLoadout";

describe("buildTestArenaLoadout", () => {
  it("packs first two non-base abilities into slots and rest into cast queue", () => {
    const built = buildTestArenaLoadout(
      ["dash", "shield", "slam", "flip"],
      ["gloves", "armor", "boots"],
    );
    expect(built.loadout.base).toBe("dash");
    expect(built.loadout.abilities).toEqual(["shield", "slam"]);
    expect(built.loadout.items).toEqual(["gloves", "armor"]);
    expect(built.extraItems).toEqual(["boots"]);
    expect(built.castAbilities).toEqual(["shield", "slam"]);
  });

  it("keeps base abilities in cast queue when only bases picked", () => {
    const built = buildTestArenaLoadout(["dash", "flip", "brace"], []);
    expect(built.loadout.base).toBe("dash");
    expect(built.castAbilities).toContain("flip");
    expect(built.castAbilities).toContain("brace");
  });
});
