import { useRender, useRenderEvent } from "@1.framework/matter4react";
import type { Body, Render } from "matter-js";
import type { RefObject } from "react";
import { renderCssSize, worldToCanvas } from "@/render/worldToCanvas";

interface Props {
  leftHeadRef: RefObject<Body | undefined>;
  rightHeadRef: RefObject<Body | undefined>;
  leftHp: number;
  rightHp: number;
  leftColor: string;
  rightColor: string;
  leftLabel: string;
  rightLabel: string;
  battleOver: boolean;
}

function worldToScreen(
  render: Render,
  x: number,
  y: number,
): { x: number; y: number } {
  return worldToCanvas(render, { x, y });
}

function drawFighterTag(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  label: string,
  color: string,
  hp: number,
  maxHp: number,
) {
  const barW = 72;
  const barH = 6;
  const pct = Math.max(0, Math.min(1, hp / maxHp));

  ctx.save();
  ctx.font = "700 11px Rubik, system-ui, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "bottom";
  ctx.fillStyle = "rgba(0,0,0,0.55)";
  const tw = ctx.measureText(label).width + 14;
  ctx.fillRect(x - tw / 2, y - 28, tw, 16);
  ctx.fillStyle = color;
  ctx.fillText(label, x, y - 14);

  ctx.fillStyle = "rgba(0,0,0,0.55)";
  ctx.fillRect(x - barW / 2, y - 10, barW, barH);
  ctx.fillStyle = color;
  ctx.fillRect(x - barW / 2, y - 10, barW * pct, barH);
  ctx.strokeStyle = "rgba(255,255,255,0.25)";
  ctx.strokeRect(x - barW / 2, y - 10, barW, barH);
  ctx.restore();
}

/** Подписи и HP над головами — чтобы фон читался как бой, а не каша. */
export function MenuBgDuelHud({
  leftHeadRef,
  rightHeadRef,
  leftHp,
  rightHp,
  leftColor,
  rightColor,
  leftLabel,
  rightLabel,
  battleOver,
}: Props) {
  const render = useRender();

  useRenderEvent(
    "afterRender",
    () => {
      const ctx = render.context;
      if (!ctx) return;
      const left = leftHeadRef.current;
      const right = rightHeadRef.current;
      if (left) {
        const p = worldToScreen(render, left.position.x, left.position.y);
        drawFighterTag(ctx, p.x, p.y, leftLabel, leftColor, leftHp, 1000);
      }
      if (right) {
        const p = worldToScreen(render, right.position.x, right.position.y);
        drawFighterTag(ctx, p.x, p.y, rightLabel, rightColor, rightHp, 1000);
      }

      if (battleOver) {
        const { width, height } = renderCssSize(render);
        ctx.save();
        ctx.font = "800 22px Unbounded, Rubik, sans-serif";
        ctx.textAlign = "center";
        ctx.fillStyle = "rgba(255,255,255,0.85)";
        ctx.fillText("KO", width * 0.42, height * 0.28);
        ctx.restore();
      }
    },
    [
      render,
      leftHeadRef,
      rightHeadRef,
      leftHp,
      rightHp,
      leftColor,
      rightColor,
      leftLabel,
      rightLabel,
      battleOver,
    ],
  );

  return null;
}
