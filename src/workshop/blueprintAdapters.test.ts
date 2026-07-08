import { describe, expect, it } from "vitest";
import {
  partsConnectedToHead,
  validateBlueprint,
} from "./blueprintAdapters";
import type { BlueprintDef } from "./blueprintTypes";

function monster(
  parts: BlueprintDef["parts"],
  links: BlueprintDef["links"] = [],
): BlueprintDef {
  return {
    id: "t",
    name: "T",
    kind: "monster",
    parts,
    links,
    meta: { maxHp: 200 },
    createdAt: 0,
  };
}

describe("partsConnectedToHead", () => {
  it("accepts single head", () => {
    expect(
      partsConnectedToHead(
        monster([{ x: 0, y: 0, radius: 20, blockKind: "head" }]),
      ),
    ).toBe(true);
  });

  it("rejects orphan body part", () => {
    const def = monster(
      [
        { x: 0, y: -20, radius: 20, blockKind: "head" },
        { x: 0, y: 20, radius: 12, blockKind: "core" },
        { x: 80, y: 20, radius: 12, blockKind: "core" },
      ],
      [{ a: 0, b: 1, type: "rigid" }],
    );
    expect(partsConnectedToHead(def)).toBe(false);
  });

  it("accepts chain from head", () => {
    const def = monster(
      [
        { x: 0, y: -20, radius: 20, blockKind: "head" },
        { x: 0, y: 20, radius: 12, blockKind: "core" },
        { x: 40, y: 40, radius: 12, blockKind: "armor" },
      ],
      [
        { a: 0, b: 1, type: "rigid" },
        { a: 1, b: 2, type: "spring" },
      ],
    );
    expect(partsConnectedToHead(def)).toBe(true);
  });
});

describe("validateBlueprint connectivity", () => {
  it("blocks monster with no links", () => {
    const check = validateBlueprint(
      monster([
        { x: 0, y: 0, radius: 20, blockKind: "head" },
        { x: 0, y: 40, radius: 12, blockKind: "core" },
      ]),
    );
    expect(check).toEqual({ ok: false, reason: "needLinks" });
  });

  it("blocks disconnected monster", () => {
    const check = validateBlueprint(
      monster(
        [
          { x: 0, y: 0, radius: 20, blockKind: "head" },
          { x: 0, y: 40, radius: 12, blockKind: "core" },
          { x: 100, y: 0, radius: 12, blockKind: "core" },
        ],
        [{ a: 0, b: 1, type: "rigid" }],
      ),
    );
    expect(check).toEqual({ ok: false, reason: "needConnected" });
  });

  it("allows connected monster", () => {
    const check = validateBlueprint(
      monster(
        [
          { x: 0, y: 0, radius: 20, blockKind: "head" },
          { x: 0, y: 40, radius: 12, blockKind: "core" },
        ],
        [{ a: 0, b: 1, type: "rigid" }],
      ),
    );
    expect(check).toEqual({ ok: true });
  });
});
