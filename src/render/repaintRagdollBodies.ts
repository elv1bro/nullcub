import Matter, { type Body, type Render as MatterRender } from "matter-js";

/** Перерисовать ragdoll поверх overlay (banter) с той же камерой, что и основной кадр. */
export function repaintRagdollBodies(
  render: MatterRender,
  ctx: CanvasRenderingContext2D,
  bodies: Body[],
): void {
  if (bodies.length === 0) return;

  if (render.options.hasBounds) {
    Matter.Render.startViewTransform(render);
  }

  Matter.Render.bodies(render, bodies, ctx);

  if (render.options.hasBounds) {
    Matter.Render.endViewTransform(render);
  }
}
