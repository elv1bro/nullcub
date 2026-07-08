import Matter from "matter-js";

/** Меню: только обнулить скорости после createStickman — как в оригинальном LeveL1. */
export function zeroMenuRagdollVelocities(composite: Matter.Composite): void {
  for (const body of composite.bodies) {
    Matter.Body.setVelocity(body, { x: 0, y: 0 });
    Matter.Body.setAngularVelocity(body, 0);
  }
}

/** Y центра невидимой платформы под ногами (как пол в LeveL1). */
export function menuPlatformY(spawnY: number): number {
  return spawnY + 95;
}
