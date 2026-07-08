import Matter, { Bodies, Composite, type Bounds } from "matter-js";

/** Статичные стены арены (как SurroundingWalls). */
export function createArenaWalls(
  bounds: Bounds,
  thick = 1000,
): Composite {
  const { min, max } = bounds;
  const wallOpts: Matter.IChamferableBodyDefinition = {
    isStatic: true,
    label: "Wall",
  };

  const bodies = [
    Bodies.rectangle(max.x / 2, min.y - thick / 2, max.x + thick, thick, wallOpts),
    Bodies.rectangle(max.x + thick / 2, max.y / 2, thick, max.y + thick, wallOpts),
    Bodies.rectangle(max.x / 2, max.y + thick / 2, max.x + thick, thick, wallOpts),
    Bodies.rectangle(min.x - thick / 2, max.y / 2, thick, max.y + thick, wallOpts),
  ];

  return Composite.create({ label: "Walls", bodies });
}
