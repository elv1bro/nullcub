import type { Composite } from "matter-js";

/** Join-клиент: только отрисовка по snapshot, без локальной физики/constraints. */
export function makeDisplayOnlyComposite(composite: Composite): void {
  composite.constraints.length = 0;
  for (const body of composite.bodies) {
    body.isSensor = true;
    body.frictionAir = 1;
    body.restitution = 0;
  }
}

export function makeDisplayOnlyComposites(composites: Composite[]): void {
  for (const composite of composites) {
    makeDisplayOnlyComposite(composite);
  }
}
