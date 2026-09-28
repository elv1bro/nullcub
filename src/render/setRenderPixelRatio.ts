import Matter from "matter-js";

/** HiDPI для Matter: cap 2 — на 3× телефонах иначе жрёт GPU. */
export const RENDER_PIXEL_RATIO_CAP = 2;

export function deviceRenderPixelRatio(
  dpr = typeof window !== "undefined" ? window.devicePixelRatio || 1 : 1,
): number {
  return Math.min(Math.max(1, dpr), RENDER_PIXEL_RATIO_CAP);
}

/** CSS size + pixelRatio для Matter.Render (резкий canvas на Retina). */
export function applyRenderSize(
  render: Matter.Render,
  width: number,
  height: number,
  pixelRatio = deviceRenderPixelRatio(),
): void {
  if (
    render.options.width === width &&
    render.options.height === height &&
    (render.options.pixelRatio || 1) === pixelRatio
  ) {
    return;
  }
  render.options.width = width;
  render.options.height = height;
  if (typeof Matter.Render.setSize === "function") {
    Matter.Render.setSize(render, width, height);
  } else {
    render.bounds.max.x = render.bounds.min.x + width;
    render.bounds.max.y = render.bounds.min.y + height;
  }
  Matter.Render.setPixelRatio(render, pixelRatio);
}
