import Matter, { Body, type Composite } from "matter-js";

/** 6 floats per body: id, x, y, angle, vx, vy */
const FLOATS_PER_BODY = 6;

export function encodeSnapshot(composites: Composite[]): Float32Array {
  const bodies = composites.flatMap((c) => c.bodies);
  const buf = new Float32Array(bodies.length * FLOATS_PER_BODY);
  let i = 0;
  for (const body of bodies) {
    buf[i++] = body.id;
    buf[i++] = body.position.x;
    buf[i++] = body.position.y;
    buf[i++] = body.angle;
    buf[i++] = body.velocity.x;
    buf[i++] = body.velocity.y;
  }
  return buf;
}

export function decodeSnapshot(
  data: Float32Array,
  world: Matter.World,
  alpha = 1,
): void {
  const all = Matter.Composite.allBodies(world);
  const byId = new Map(all.map((b) => [b.id, b]));

  for (let i = 0; i < data.length; i += FLOATS_PER_BODY) {
    const id = data[i]!;
    const body = byId.get(id);
    if (!body || body.isStatic) continue;
    const x = data[i + 1]!;
    const y = data[i + 2]!;
    const angle = data[i + 3]!;
    const vx = data[i + 4]!;
    const vy = data[i + 5]!;

    if (alpha >= 1) {
      Body.setPosition(body, { x, y });
      Body.setAngle(body, angle);
      Body.setVelocity(body, { x: vx, y: vy });
    } else {
      Body.setPosition(body, {
        x: body.position.x + (x - body.position.x) * alpha,
        y: body.position.y + (y - body.position.y) * alpha,
      });
      Body.setAngle(body, body.angle + (angle - body.angle) * alpha);
    }
  }
}

export function snapshotByteSize(composites: Composite[]): number {
  return composites.reduce((n, c) => n + c.bodies.length, 0) * FLOATS_PER_BODY * 4;
}

/**
 * Ordered-кодек: тела матчатся по индексу, а не по body.id.
 * Нужен для dedicated-сервера — id тел на сервере и клиенте не совпадают,
 * но порядок создания (боец A, боец B, предметы) детерминирован.
 */
const FLOATS_PER_BODY_ORDERED = 5;

export function encodeBodiesOrdered(bodies: Body[]): Float32Array {
  const buf = new Float32Array(bodies.length * FLOATS_PER_BODY_ORDERED);
  let i = 0;
  for (const body of bodies) {
    buf[i++] = body.position.x;
    buf[i++] = body.position.y;
    buf[i++] = body.angle;
    buf[i++] = body.velocity.x;
    buf[i++] = body.velocity.y;
  }
  return buf;
}

export function decodeBodiesOrdered(
  data: Float32Array,
  bodies: Body[],
  alpha = 1,
  opts?: { positionsOnly?: boolean },
): void {
  const count = Math.min(bodies.length, Math.floor(data.length / FLOATS_PER_BODY_ORDERED));
  const positionsOnly = opts?.positionsOnly ?? false;
  for (let n = 0; n < count; n++) {
    const body = bodies[n]!;
    if (body.isStatic) continue;
    const i = n * FLOATS_PER_BODY_ORDERED;
    const x = data[i]!;
    const y = data[i + 1]!;
    const angle = data[i + 2]!;
    const vx = data[i + 3]!;
    const vy = data[i + 4]!;

    if (alpha >= 1) {
      Body.setPosition(body, { x, y });
      Body.setAngle(body, angle);
      if (!positionsOnly) {
        Body.setVelocity(body, { x: vx, y: vy });
      }
    } else {
      Body.setPosition(body, {
        x: body.position.x + (x - body.position.x) * alpha,
        y: body.position.y + (y - body.position.y) * alpha,
      });
      Body.setAngle(body, body.angle + (angle - body.angle) * alpha);
      if (!positionsOnly) {
        Body.setVelocity(body, { x: vx, y: vy });
      }
    }
  }
}

/** Линейная интерполяция между двумя ordered-снапшотами в out. */
export function lerpBodiesOrdered(
  from: Float32Array,
  to: Float32Array,
  alpha: number,
  out: Float32Array,
): void {
  const n = Math.min(from.length, to.length, out.length);
  const a = Math.max(0, Math.min(1, alpha));
  for (let i = 0; i < n; i++) {
    out[i] = from[i]! + (to[i]! - from[i]!) * a;
  }
}
