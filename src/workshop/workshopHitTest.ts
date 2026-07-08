import Matter, { type Composite, type Vector } from "matter-js";

export function bodyIndexAt(composite: Composite, point: Vector): number | null {
  const hit = Matter.Query.point(composite.bodies, point)[0];
  if (!hit) return null;
  return composite.bodies.findIndex((b) => b.id === hit.id);
}

export function linkIndexAt(
  composite: Composite,
  links: { a: number; b: number }[],
  point: Vector,
  threshold = 14,
): number | null {
  let best: { index: number; dist: number } | null = null;

  for (let i = 0; i < links.length; i++) {
    const link = links[i]!;
    const a = composite.bodies[link.a]?.position;
    const b = composite.bodies[link.b]?.position;
    if (!a || !b) continue;
    const dist = distancePointToSegment(point, a, b);
    if (dist <= threshold && (!best || dist < best.dist)) {
      best = { index: i, dist };
    }
  }

  return best?.index ?? null;
}

function distancePointToSegment(
  p: Vector,
  a: Vector,
  b: Vector,
): number {
  const abx = b.x - a.x;
  const aby = b.y - a.y;
  const lenSq = abx * abx + aby * aby;
  if (lenSq < 0.001) {
    return Math.hypot(p.x - a.x, p.y - a.y);
  }
  const t = Math.max(
    0,
    Math.min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq),
  );
  const cx = a.x + t * abx;
  const cy = a.y + t * aby;
  return Math.hypot(p.x - cx, p.y - cy);
}

export function canvasToWorld(
  canvas: HTMLCanvasElement,
  bounds: Matter.Bounds,
  clientX: number,
  clientY: number,
): Vector {
  const rect = canvas.getBoundingClientRect();
  const nx = (clientX - rect.left) / rect.width;
  const ny = (clientY - rect.top) / rect.height;
  return {
    x: bounds.min.x + nx * (bounds.max.x - bounds.min.x),
    y: bounds.min.y + ny * (bounds.max.y - bounds.min.y),
  };
}
