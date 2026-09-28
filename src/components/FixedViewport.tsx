import { useRender, useRenderEvent } from "@1.framework/matter4react";
import Matter, { type Body } from "matter-js";
import { useLayoutEffect } from "react";
import { applyRenderSize } from "@/render/setRenderPixelRatio";

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
    applyRenderSize(render, width, height);
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
