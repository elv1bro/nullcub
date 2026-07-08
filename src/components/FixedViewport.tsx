import { useRender, useRenderEvent } from "@1.framework/matter4react";
import Matter, { type Body } from "matter-js";
import { useLayoutEffect } from "react";

interface Props {
  width: number;
  height: number;
  padding?: number;
  protagonists: Body[];
}

/** Камера фиксированного размера (меню-превью, не на весь экран). */
export function FixedViewport({
  width,
  height,
  padding = 48,
  protagonists,
}: Props) {
  const render = useRender();

  useLayoutEffect(() => {
    render.options.width = width;
    render.options.height = height;
    render.canvas.width = width;
    render.canvas.height = height;
  }, [render, width, height]);

  useRenderEvent(
    "beforeRender",
    () => {
      Matter.Render.lookAt(
        render,
        protagonists,
        Matter.Vector.create(padding, padding),
        true,
      );
    },
    [render, protagonists, padding],
  );

  return null;
}
