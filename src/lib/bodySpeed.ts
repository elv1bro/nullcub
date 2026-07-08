import { Body, Vector } from "matter-js";
import { MAX_BODY_SPEED } from "./battleTuning";

/** Matter beforeUpdate: delta в ms; формула moveBody исторически использует delta×1000. */
export function moveBodyDeltaMs(event: { delta?: number }): number {
  const frameMs =
    typeof event.delta === "number" && event.delta > 0
      ? event.delta
      : 1000 / 60;
  return Math.max(frameMs * 1_000, 1);
}

export function clampBodySpeed(body: Body): void {
  const speed = Vector.magnitude(body.velocity);
  if (speed <= MAX_BODY_SPEED) return;
  Body.setVelocity(body, Vector.mult(Vector.normalise(body.velocity), MAX_BODY_SPEED));
}

export function clampCompositeSpeed(composite: {
  bodies: Body[];
}): void {
  for (const body of composite.bodies) {
    clampBodySpeed(body);
  }
}
