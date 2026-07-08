/** Снимок T-позы ragdoll для способности reset. */

import { Body, Composite, Vector } from "matter-js";

export type PosePart = {
  bodyId: number;
  localOffset: Vector;
  relAngle: number;
};

export type PoseSnapshot = {
  headId: number;
  parts: PosePart[];
};

export function capturePoseSnapshot(composite: Composite): PoseSnapshot | null {
  const head = composite.bodies.find((b) => b.label === "Head");
  if (!head) return null;

  const parts: PosePart[] = [];
  for (const body of composite.bodies) {
    if (body.id === head.id) continue;
    const worldOffset = Vector.sub(body.position, head.position);
    parts.push({
      bodyId: body.id,
      localOffset: Vector.rotate(worldOffset, -head.angle),
      relAngle: body.angle - head.angle,
    });
  }

  return { headId: head.id, parts };
}

/**
 * Держит T-позу (способность reset).
 * Голова тоже замедляется.
 */
export function stepPoseReset(
  composite: Composite,
  snap: PoseSnapshot,
  progress: number,
): void {
  stepPoseHold(composite, snap, progress, { dampHead: true });
}

function stepPoseHold(
  composite: Composite,
  snap: PoseSnapshot,
  progress: number,
  opts: { dampHead: boolean; strength?: number },
): void {
  const head = composite.bodies.find((b) => b.id === snap.headId);
  if (!head) return;

  const t = Math.max(0, Math.min(1, progress));
  const strength = opts.strength ?? 1;
  const pull = (0.1 + t * 0.38) * strength;
  const damp = 0.82 + t * 0.1;

  for (const part of snap.parts) {
    const body = composite.bodies.find((b) => b.id === part.bodyId);
    if (!body) continue;

    const targetPos = Vector.add(
      head.position,
      Vector.rotate(part.localOffset, head.angle),
    );
    const delta = Vector.sub(targetPos, body.position);
    Body.applyForce(
      body,
      body.position,
      Vector.mult(delta, pull * body.mass * 0.0014),
    );

    const targetAngle = head.angle + part.relAngle;
    let angleDiff = targetAngle - body.angle;
    while (angleDiff > Math.PI) angleDiff -= Math.PI * 2;
    while (angleDiff < -Math.PI) angleDiff += Math.PI * 2;
    Body.setAngularVelocity(
      body,
      body.angularVelocity * damp + angleDiff * pull * 0.12,
    );

    if (opts.dampHead) {
      Body.setVelocity(body, Vector.mult(body.velocity, damp));
    } else {
      Body.setVelocity(
        body,
        Vector.add(Vector.mult(body.velocity, 0.55), Vector.mult(head.velocity, 0.45)),
      );
    }
  }

  if (opts.dampHead) {
    Body.setAngularVelocity(head, head.angularVelocity * damp);
    Body.setVelocity(head, Vector.mult(head.velocity, damp));
  }
}

/** Удерживает ragdoll в сохранённой позе (меню без цепей, reset). */
export function holdPoseSnapshot(composite: Composite, snap: PoseSnapshot): void {
  stepPoseHold(composite, snap, 1, { dampHead: true, strength: 1.4 });
}
