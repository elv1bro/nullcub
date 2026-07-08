import { describe, expect, it } from "vitest";
import { generateMonsterName } from "./generateMonsterName";

describe("generateMonsterName", () => {
  it("returns MONSTER + 4 uppercase alphanumeric chars", () => {
    const name = generateMonsterName();
    expect(name).toMatch(/^MONSTER [A-Z0-9]{4}$/);
  });
});
