import { useCallback, useEffect, useRef, useState } from "react";
import type Matter from "matter-js";
import type { BlockTemplate } from "./blockCatalog";
import { canvasToWorld } from "./workshopHitTest";

type Ghost = { x: number; y: number; template: BlockTemplate };

export function usePaletteDrag(options: {
  canvas: HTMLCanvasElement | undefined;
  render: Matter.Render | undefined;
  disabled?: boolean;
  onDrop: (world: Matter.Vector, template: BlockTemplate) => void;
}) {
  const { disabled } = options;
  const [ghost, setGhost] = useState<Ghost | null>(null);
  const draggingRef = useRef<BlockTemplate | null>(null);
  const optRef = useRef(options);
  optRef.current = options;

  const startDrag = useCallback(
    (template: BlockTemplate) => {
      if (disabled) return;
      draggingRef.current = template;
    },
    [disabled],
  );

  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      if (!draggingRef.current) return;
      setGhost({ x: e.clientX, y: e.clientY, template: draggingRef.current });
    };

    const onUp = (e: MouseEvent) => {
      const tpl = draggingRef.current;
      draggingRef.current = null;
      setGhost(null);
      if (!tpl) return;

      const { canvas, render, onDrop } = optRef.current;
      if (!canvas || !render) return;

      const rect = canvas.getBoundingClientRect();
      const inside =
        e.clientX >= rect.left &&
        e.clientX <= rect.right &&
        e.clientY >= rect.top &&
        e.clientY <= rect.bottom;
      if (!inside) return;

      const world = canvasToWorld(canvas, render.bounds, e.clientX, e.clientY);
      if (world) onDrop(world, tpl);
    };

    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    return () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    };
  }, []);

  return { ghost, startDrag };
}
