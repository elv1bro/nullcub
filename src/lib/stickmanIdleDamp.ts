import { Body, Vector, type Composite, type Vector as Vec } from "matter-js";

/** Гасит боковую скорость COM — idle на полу не «уползает» вбок. */
export function dampStickmanLateralDrift(
  composite: Composite,
  factor = 0.18,
): void {
  if (composite.bodies.length === 0) return;
  let mvx = 0;
  let m = 0;
  for (const b of composite.bodies) {
    mvx += b.velocity.x * b.mass;
    m += b.mass;
  }
  const comVx = mvx / Math.max(m, 1e-6);
  if (Math.abs(comVx) < 0.02) return;

  const kill = comVx * factor;
  for (const b of composite.bodies) {
    Body.setVelocity(b, {
      x: b.velocity.x - kill,
      y: b.velocity.y,
    });
  }
}

/** Слабо тянет COM к якорю по X (симметричное «провисание» без уползания). */
export function pullStickmanComToX(
  composite: Composite,
  anchorX: number,
  strength = 0.0008,
): void {
  let mx = 0;
  let m = 0;
  for (const b of composite.bodies) {
    mx += b.position.x * b.mass;
    m += b.mass;
  }
  const comX = mx / Math.max(m, 1e-6);
  const error = anchorX - comX;
  if (Math.abs(error) < 0.5) return;

  for (const b of composite.bodies) {
    Body.applyForce(b, b.position, {
      x: error * strength * b.mass,
      y: 0,
    });
  }
}

export function stickmanCom(composite: Composite): Vec {
  let mx = 0;
  let my = 0;
  let m = 0;
  for (const b of composite.bodies) {
    mx += b.position.x * b.mass;
    my += b.position.y * b.mass;
    m += b.mass;
  }
  const inv = 1 / Math.max(m, 1e-6);
  return Vector.create(mx * inv, my * inv);
}
