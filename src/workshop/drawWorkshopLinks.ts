import type Matter from "matter-js";
import { type MonsterLinkType } from "@/monster/linkTypes";
import { blueprintLinkStroke } from "@/workshop/workshopPartRender";
import { worldToCanvas } from "@/render/worldToCanvas";

type LinkLike = { a: number; b: number; type: MonsterLinkType };

function applyLinkDash(ctx: CanvasRenderingContext2D, type: MonsterLinkType): void {
  if (type === "spring") ctx.setLineDash([10, 7]);
  else if (type === "rope") ctx.setLineDash([4, 6]);
  else ctx.setLineDash([]);
}

export function drawWorkshopLink(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  ax: number,
  ay: number,
  bx: number,
  by: number,
  type: MonsterLinkType,
  lineWidth = 3,
): void {
  const a = worldToCanvas(render, { x: ax, y: ay });
  const b = worldToCanvas(render, { x: bx, y: by });
  ctx.save();
  ctx.strokeStyle = blueprintLinkStroke(type);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = "round";
  applyLinkDash(ctx, type);
  ctx.beginPath();
  ctx.moveTo(a.x, a.y);
  ctx.lineTo(b.x, b.y);
  ctx.stroke();
  ctx.restore();
}

export function drawWorkshopLinks(
  ctx: CanvasRenderingContext2D,
  render: Matter.Render,
  composite: Matter.Composite,
  links: LinkLike[],
): void {
  for (const link of links) {
    const bodyA = composite.bodies[link.a];
    const bodyB = composite.bodies[link.b];
    if (!bodyA || !bodyB) continue;
    drawWorkshopLink(
      ctx,
      render,
      bodyA.position.x,
      bodyA.position.y,
      bodyB.position.x,
      bodyB.position.y,
      link.type,
    );
  }
}
