import type Matter from "matter-js";

export function worldToCanvas(
  render: Matter.Render,
  point: Matter.Vector,
): { x: number; y: number; scale: number } {
  const { canvas, bounds } = render;
  const bw = bounds.max.x - bounds.min.x;
  const bh = bounds.max.y - bounds.min.y;
  const scale = Math.min(canvas.width / bw, canvas.height / bh);
  return {
    x: (point.x - bounds.min.x) * scale,
    y: (point.y - bounds.min.y) * scale,
    scale,
  };
}
