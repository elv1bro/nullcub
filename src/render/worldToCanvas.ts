import type Matter from "matter-js";

/** CSS-размер Matter canvas (после endViewTransform рисуем в этих единицах). */
export function renderCssSize(render: Matter.Render): {
  width: number;
  height: number;
  pixelRatio: number;
} {
  const pixelRatio = render.options.pixelRatio || 1;
  const width =
    render.options.width ??
    (render.canvas ? render.canvas.width / pixelRatio : 0);
  const height =
    render.options.height ??
    (render.canvas ? render.canvas.height / pixelRatio : 0);
  return { width, height, pixelRatio };
}

/**
 * Мир → экран в CSS-пикселях.
 * afterRender идёт после Matter.endViewTransform (scale = pixelRatio),
 * поэтому координаты должны быть CSS, не backing-store.
 */
export function worldToCanvas(
  render: Matter.Render,
  point: Matter.Vector,
): { x: number; y: number; scale: number } {
  const { bounds } = render;
  const { width, height } = renderCssSize(render);
  const bw = bounds.max.x - bounds.min.x;
  const bh = bounds.max.y - bounds.min.y;
  const scale = Math.min(width / bw, height / bh);
  return {
    x: (point.x - bounds.min.x) * scale,
    y: (point.y - bounds.min.y) * scale,
    scale,
  };
}
