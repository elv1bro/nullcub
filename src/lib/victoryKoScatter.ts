/** KO: части ragdoll отваливаются, разлетаются и тихо падают. */

import { Body, Composite, Vector, type Engine } from "matter-js";

export type KoScatteredComposite = Composite & { koScattered?: boolean };

export function markKoScattered(composite: Composite): void {
  (composite as KoScatteredComposite).koScattered = true;
}

export function isKoScattered(composite: Composite | undefined): boolean {
  return !!(composite as KoScatteredComposite | undefined)?.koScattered;
}

export function isKoScatteredId(
  compositeId: number,
  composites: Composite[],
): boolean {
  return isKoScattered(composites.find((c) => c.id === compositeId));
}
import {
  KO_SCATTER_SPEED_MAX,
  KO_SCATTER_SPEED_MIN,
} from "./battleTuning";

export function findHead(composite: Composite): Body | undefined {
  return composite.bodies.find((b) => b.label === "Head");
}

/** Снимает все constraints ragdoll (в т.ч. вложенные в world). */
export function releaseRagdollConstraints(
  _engine: Engine,
  composite: Composite,
): void {
  const constraints = Composite.allConstraints(composite);
  for (const constraint of constraints) {
    Composite.remove(composite, constraint);
  }
}

export function scatterKoRagdoll(engine: Engine, composite: Composite): void {
  releaseRagdollConstraints(engine, composite);

  const head = findHead(composite);
  const origin = head?.position ?? composite.bodies[0]?.position;
  if (!origin) return;

  for (const body of composite.bodies) {
    if (body.isStatic) Body.setStatic(body, false);
    if (body.isSleeping) Body.set(body, { isSleeping: false });

    const offset = Vector.sub(body.position, origin);
    let dir =
      Vector.magnitude(offset) > 4
        ? Vector.normalise(offset)
        : Vector.create(
            Math.cos(Math.random() * Math.PI * 2),
            Math.sin(Math.random() * Math.PI * 2),
          );

    const jitter = (Math.random() - 0.5) * 0.5;
    const cos = Math.cos(jitter);
    const sin = Math.sin(jitter);
    dir = Vector.create(dir.x * cos - dir.y * sin, dir.x * sin + dir.y * cos);

    const speed =
      KO_SCATTER_SPEED_MIN +
      Math.random() * (KO_SCATTER_SPEED_MAX - KO_SCATTER_SPEED_MIN);

    Body.setVelocity(body, {
      x: dir.x * speed + body.velocity.x * 0.2,
      y: dir.y * speed + body.velocity.y * 0.2 - 1.5,
    });
    Body.setAngularVelocity(body, (Math.random() - 0.5) * 1.4);
    body.frictionAir = Math.max(body.frictionAir, 0.035);
    body.restitution = Math.min(body.restitution + 0.05, 0.35);
  }

  markKoScattered(composite);
}
