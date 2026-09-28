import { useEffect, type MutableRefObject } from "react";
import Matter, { Body, type Composite } from "matter-js";
import type { MonsterLinkType } from "@/monster/linkTypes";
import { rebuildCompositeLinks } from "@/monster/linkTypes";
import { snapToGrid } from "@/workshop/blueprintGrid";
import {
  bodyIndexAt,
  canvasToWorld,
  linkIndexAt,
} from "@/workshop/workshopHitTest";
import type { WorkshopTool } from "@/workshop/useWorkshopValidation";

export type WorkshopLinkRecord = {
  a: number;
  b: number;
  type: MonsterLinkType;
};

type DragRef = {
  x: number;
  y: number;
  fromBody: number | null;
  linkMode: boolean;
};

type Opts = {
  canvas: HTMLCanvasElement | null | undefined;
  render: Matter.Render | null | undefined;
  composite: Composite | undefined;
  physicsPreview: boolean;
  tool: WorkshopTool;
  linkType: MonsterLinkType;
  linksRef: MutableRefObject<WorkshopLinkRecord[]>;
  dragRef: MutableRefObject<DragRef | null>;
  setSelectedLinkIndex: (index: number | null) => void;
  setSelectedPartIndex: (index: number | null) => void;
  setLinkPreview: (
    preview: { from: number; x: number; y: number } | null,
  ) => void;
  linkParts: (a: number, b: number, type: MonsterLinkType) => void;
  selectPartAt: (index: number) => void;
  bumpRevision: () => void;
};

/**
 * Canvas input: Move tool = drag parts; Link tool = create/select links.
 * Shift+LMB in Move remains a link shortcut.
 */
export function useWorkshopCanvasInput(opts: Opts): void {
  const {
    canvas,
    render,
    composite,
    physicsPreview,
    tool,
    linkType,
    linksRef,
    dragRef,
    setSelectedLinkIndex,
    setSelectedPartIndex,
    setLinkPreview,
    linkParts,
    selectPartAt,
    bumpRevision,
  } = opts;

  useEffect(() => {
    if (!canvas || !composite || !render) return;

    const pointFromEvent = (clientX: number, clientY: number) =>
      canvasToWorld(canvas, render.bounds, clientX, clientY);

    const onContextMenu = (e: MouseEvent) => {
      e.preventDefault();
      if (physicsPreview) return;
      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;
      const index = bodyIndexAt(composite, point);
      if (index !== null) selectPartAt(index);
      else {
        setSelectedPartIndex(null);
        setSelectedLinkIndex(null);
      }
    };

    const onDown = (e: MouseEvent) => {
      if (e.button !== 0 || physicsPreview) return;
      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;

      const hitIndex = bodyIndexAt(composite, point);
      const linkMode = tool === "link" || e.shiftKey;

      if (hitIndex !== null) {
        dragRef.current = {
          x: e.clientX,
          y: e.clientY,
          fromBody: hitIndex,
          linkMode,
        };
        if (linkMode) {
          setLinkPreview({ from: hitIndex, x: point.x, y: point.y });
          setSelectedLinkIndex(null);
        } else {
          setSelectedPartIndex(hitIndex);
          setSelectedLinkIndex(null);
          setLinkPreview(null);
        }
        return;
      }

      // Click empty / on link
      dragRef.current = {
        x: e.clientX,
        y: e.clientY,
        fromBody: null,
        linkMode: false,
      };
      if (tool === "link" || !e.shiftKey) {
        const linkIdx = linkIndexAt(composite, linksRef.current, point);
        if (linkIdx !== null) {
          setSelectedLinkIndex(linkIdx);
          setSelectedPartIndex(null);
        } else {
          setSelectedLinkIndex(null);
        }
      }
    };

    const onMove = (e: MouseEvent) => {
      const drag = dragRef.current;
      if (!drag || drag.fromBody === null) return;
      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;

      if (drag.linkMode) {
        const targetIndex = bodyIndexAt(composite, point);
        const targetBody =
          targetIndex !== null && targetIndex !== drag.fromBody
            ? composite.bodies[targetIndex]
            : null;
        const end = targetBody?.position ?? point;
        setLinkPreview({ from: drag.fromBody, x: end.x, y: end.y });
        return;
      }

      const body = composite.bodies[drag.fromBody];
      if (body) {
        Body.setPosition(body, snapToGrid(point));
        Body.setVelocity(body, { x: 0, y: 0 });
        rebuildCompositeLinks(composite, linksRef.current);
        bumpRevision();
      }
    };

    const onUp = (e: MouseEvent) => {
      if (e.button !== 0 || physicsPreview) return;
      const drag = dragRef.current;
      dragRef.current = null;
      setLinkPreview(null);
      if (!drag) return;

      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;

      const dx = e.clientX - drag.x;
      const dy = e.clientY - drag.y;
      const moved = dx * dx + dy * dy > 36;
      const endBody = bodyIndexAt(composite, point);

      if (
        drag.linkMode &&
        drag.fromBody !== null &&
        endBody !== null &&
        drag.fromBody !== endBody
      ) {
        linkParts(drag.fromBody, endBody, linkType);
        return;
      }

      // Click on link line (no body) → select; second click / Delete deletes via UI
      if (!moved && drag.fromBody === null) {
        const linkIdx = linkIndexAt(composite, linksRef.current, point);
        if (linkIdx !== null) {
          setSelectedLinkIndex(linkIdx);
          setSelectedPartIndex(null);
        }
      }
    };

    canvas.addEventListener("contextmenu", onContextMenu);
    canvas.addEventListener("mousedown", onDown);
    canvas.addEventListener("mousemove", onMove);
    canvas.addEventListener("mouseup", onUp);
    return () => {
      canvas.removeEventListener("contextmenu", onContextMenu);
      canvas.removeEventListener("mousedown", onDown);
      canvas.removeEventListener("mousemove", onMove);
      canvas.removeEventListener("mouseup", onUp);
    };
  }, [
    canvas,
    render,
    composite,
    physicsPreview,
    tool,
    linkType,
    linksRef,
    dragRef,
    setSelectedLinkIndex,
    setSelectedPartIndex,
    setLinkPreview,
    linkParts,
    selectPartAt,
    bumpRevision,
  ]);
}
