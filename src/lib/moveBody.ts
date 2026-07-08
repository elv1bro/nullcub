//

import { Body, Engine, Vector, type IEventTimestamped } from "matter-js";
import { moveBodyDeltaMs } from "./bodySpeed";

//

const SPEED = 40;

/** moveBody negates direction — same convention as PlayerMovementInput (W = {0,1} → force up). */
export function toMoveInput(worldDir: Vector): Vector {
  return Vector.neg(worldDir);
}

//

export function moveBody(body: Body) {
  return (
    event: IEventTimestamped<Engine>,
    direction: Vector,
    speed = SPEED
  ) => {
    const dt = moveBodyDeltaMs(event);
    Body.applyForce(
      body,
      body.position,
      Vector.mult(direction, (-1 * speed * body.mass) / dt),
    );
  };
}
