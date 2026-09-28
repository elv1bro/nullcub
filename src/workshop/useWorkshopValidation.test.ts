import { describe, expect, it } from "vitest";
import { orphanPartIndices } from "./blueprintAdapters";
import type { BlueprintDef } from "./blueprintTypes";
import {
  buildWorkshopDraft,
  evaluateWorkshopDraft,
} from "./useWorkshopValidation";
import { createBlockMeta } from "./blockMeta";

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

describe("orphanPartIndices", () => {
  it("returns empty when all parts reach head", () => {
    const def = monster(
      [
        { x: 0, y: -20, radius: 20, blockKind: "head" },
        { x: 0, y: 20, radius: 12, blockKind: "core" },
      ],
      [{ a: 0, b: 1, type: "rigid" }],
    );
    expect(orphanPartIndices(def)).toEqual([]);
  });

  it("lists disconnected part indices", () => {
    const def = monster(
      [
        { x: 0, y: -20, radius: 20, blockKind: "head" },
        { x: 0, y: 20, radius: 12, blockKind: "core" },
        { x: 80, y: 20, radius: 12, blockKind: "core" },
      ],
      [{ a: 0, b: 1, type: "rigid" }],
    );
    expect(orphanPartIndices(def)).toEqual([2]);
  });
});

describe("evaluateWorkshopDraft", () => {
  it("marks connected head+core ready", () => {
    const view = evaluateWorkshopDraft(
      monster(
        [
          { x: 0, y: 0, radius: 20, blockKind: "head" },
          { x: 0, y: 40, radius: 12, blockKind: "core" },
        ],
        [{ a: 0, b: 1, type: "rigid" }],
      ),
    );
    expect(view.ready).toBe(true);
    expect(view.orphans).toEqual([]);
    expect(view.hasHead).toBe(true);
    expect(view.hasHurtbox).toBe(true);
    expect(view.hasLinks).toBe(true);
  });

  it("exposes orphans when a part is disconnected", () => {
    const view = evaluateWorkshopDraft(
      monster(
        [
          { x: 0, y: 0, radius: 20, blockKind: "head" },
          { x: 0, y: 40, radius: 12, blockKind: "core" },
          { x: 100, y: 0, radius: 12, blockKind: "core" },
        ],
        [{ a: 0, b: 1, type: "rigid" }],
      ),
    );
    expect(view.ready).toBe(false);
    expect(view.orphans).toEqual([2]);
    expect(view.check).toEqual({ ok: false, reason: "needConnected" });
  });
});

describe("buildWorkshopDraft", () => {
  it("snapshots bodies + meta into a blueprint", () => {
    const draft = buildWorkshopDraft({
      kind: "monster",
      name: "Snap",
      id: "id-1",
      meta: { maxHp: 200 },
      bodies: [
        { position: { x: 100, y: 80 }, circleRadius: 20 },
        { position: { x: 100, y: 120 }, circleRadius: 12 },
      ],
      partsMeta: [createBlockMeta("head"), createBlockMeta("core")],
      links: [{ a: 0, b: 1, type: "spring" }],
    });
    expect(draft.parts).toHaveLength(2);
    expect(draft.parts[0]?.blockKind).toBe("head");
    expect(draft.links).toEqual([{ a: 0, b: 1, type: "spring" }]);
    expect(evaluateWorkshopDraft(draft).ready).toBe(true);
  });
});
