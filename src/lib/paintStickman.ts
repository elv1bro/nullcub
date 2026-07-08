import Matter from "matter-js";
import { isSaveBody } from "./isSaveBody";

/** Основной цвет — всё тело; второй — центр кончиков (рисуется в afterRender). */
export function applyPlayerColors(
  composite: Matter.Composite,
  bodyColor: string,
  _limbTipColor: string,
): void {
  for (const body of composite.bodies) {
    if (body.label === "Head") continue;

    const r = body.circleRadius ?? 10;
    body.render.fillStyle = bodyColor;
    body.render.strokeStyle = bodyColor;
    body.render.lineWidth = isSaveBody(body)
      ? Math.max(1.5, r * 0.1)
      : Math.max(1, r * 0.08);
  }
}

export function compositeSpeed(composite: Matter.Composite): number {
  if (composite.bodies.length === 0) return 0;
  const sum = composite.bodies.reduce(
    (acc, b) => acc + Matter.Vector.magnitude(b.velocity),
    0,
  );
  return sum / composite.bodies.length;
}
