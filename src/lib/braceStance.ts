/** Стойка: собрать ragdoll без жёсткой фиксации позы — работает и на высокой скорости. */

import { Body, Composite, Vector } from "matter-js";

type StiffnessEntry = { constraint: Matter.Constraint; stiffness: number };

const ACTIVATE_SPIN_KEEP = 0.22;
const FRAME_SPIN_DAMP = 0.88;
const LIMB_VEL_DAMP = 0.94;
const LIMB_HEAD_BLEND = 0.16;
const STIFFNESS_MULT = 1.55;

export function activateBraceBurst(composite: Composite): StiffnessEntry[] {
  for (const body of composite.bodies) {
    Body.setAngularVelocity(body, body.angularVelocity * ACTIVATE_SPIN_KEEP);
  }

  const entries: StiffnessEntry[] = [];
  for (const constraint of composite.constraints) {
    entries.push({ constraint, stiffness: constraint.stiffness });
    constraint.stiffness = Math.min(1, constraint.stiffness * STIFFNESS_MULT);
  }
  return entries;
}

export function restoreBraceStiffness(entries: StiffnessEntry[]): void {
  for (const { constraint, stiffness } of entries) {
    constraint.stiffness = stiffness;
  }
}

/** Каждый кадр: меньше кручения, конечности мягко следуют за головой. */
export function stepBraceStance(composite: Composite): void {
  const head = composite.bodies.find((b) => b.label === "Head");
  const headVel = head?.velocity ?? Vector.create(0, 0);

  for (const body of composite.bodies) {
    Body.setAngularVelocity(body, body.angularVelocity * FRAME_SPIN_DAMP);

    if (head && body.id !== head.id) {
      // Сначала мягко подтягиваем скорость к голове (lerp), потом гасим.
      // Сумма коэффициентов ≤ 1, иначе скорость разгонялась бы каждый кадр.
      const blended = Vector.add(
        Vector.mult(body.velocity, 1 - LIMB_HEAD_BLEND),
        Vector.mult(headVel, LIMB_HEAD_BLEND),
      );
      Body.setVelocity(body, Vector.mult(blended, LIMB_VEL_DAMP));
    }
  }
}
