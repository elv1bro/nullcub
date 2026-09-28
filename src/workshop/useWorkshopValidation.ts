import { useMemo } from "react";
import type { BlockMeta } from "./blockMeta";
import type { BlueprintDef, WorkshopKind } from "./blueprintTypes";
import {
  orphanPartIndices,
  validateBlueprint,
} from "./blueprintAdapters";
import type { MonsterLinkType } from "@/monster/linkTypes";

export type WorkshopTool = "move" | "link";

export type WorkshopValidationView = {
  draft: BlueprintDef;
  check: ReturnType<typeof validateBlueprint>;
  orphans: number[];
  ready: boolean;
  hasHead: boolean;
  hasHurtbox: boolean;
  hasLinks: boolean;
};

/** Снимок текущего холста → live-валидация для UI. */
export function buildWorkshopDraft(opts: {
  kind: WorkshopKind;
  name: string;
  id: string;
  meta: BlueprintDef["meta"];
  bodies: Array<{ position: { x: number; y: number }; circleRadius?: number }>;
  partsMeta: BlockMeta[];
  links: { a: number; b: number; type: MonsterLinkType }[];
}): BlueprintDef {
  const positions = opts.bodies.map((b) => ({
    x: b.position.x,
    y: b.position.y,
  }));
  const center =
    positions.length === 0
      ? { x: 0, y: 0 }
      : positions.reduce(
          (acc, p) => ({ x: acc.x + p.x, y: acc.y + p.y }),
          { x: 0, y: 0 },
        );
  const c =
    positions.length === 0
      ? { x: 0, y: 0 }
      : { x: center.x / positions.length, y: center.y / positions.length };

  return {
    id: opts.id,
    name: opts.name,
    kind: opts.kind,
    parts: opts.bodies.map((body, index) => ({
      x: body.position.x - c.x,
      y: body.position.y - c.y,
      radius: body.circleRadius ?? 10,
      blockKind: opts.partsMeta[index]?.blockKind ?? "core",
    })),
    links: opts.links.map((l) => ({ ...l })),
    meta: opts.meta,
    createdAt: Date.now(),
  };
}

export function evaluateWorkshopDraft(
  draft: BlueprintDef,
): WorkshopValidationView {
  const check = validateBlueprint(draft);
  const orphans =
    draft.kind === "monster" ? orphanPartIndices(draft) : [];
  const hasHead = draft.parts.some((p) => p.blockKind === "head");
  const hasHurtbox = draft.parts.some(
    (p) => p.blockKind === "core" || p.blockKind === "head",
  );
  const hasLinks = draft.parts.length <= 1 || draft.links.length > 0;
  return {
    draft,
    check,
    orphans,
    ready: check.ok,
    hasHead,
    hasHurtbox,
    hasLinks,
  };
}

export function useWorkshopValidation(opts: {
  kind: WorkshopKind;
  name: string;
  id: string;
  meta: BlueprintDef["meta"];
  bodyCount: number;
  /** Сериализуемый ключ для пересчёта (позиции + links + meta kinds). */
  revision: string;
  getBodies: () => Array<{
    position: { x: number; y: number };
    circleRadius?: number;
  }>;
  getPartsMeta: () => BlockMeta[];
  getLinks: () => { a: number; b: number; type: MonsterLinkType }[];
}): WorkshopValidationView {
  return useMemo(() => {
    void opts.revision;
    void opts.bodyCount;
    const draft = buildWorkshopDraft({
      kind: opts.kind,
      name: opts.name,
      id: opts.id,
      meta: opts.meta,
      bodies: opts.getBodies(),
      partsMeta: opts.getPartsMeta(),
      links: opts.getLinks(),
    });
    return evaluateWorkshopDraft(draft);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- revision encodes mutable refs
  }, [
    opts.kind,
    opts.name,
    opts.id,
    opts.meta,
    opts.bodyCount,
    opts.revision,
  ]);
}
