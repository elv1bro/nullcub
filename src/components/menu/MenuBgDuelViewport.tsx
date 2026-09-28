import { useRender, useRenderEvent } from "@1.framework/matter4react";
import Matter, { type Body } from "matter-js";
import { useRef, type RefObject } from "react";

interface Props {
  arenaSize: number;
  leftHeadRef: RefObject<Body | undefined>;
  rightHeadRef: RefObject<Body | undefined>;
}

/** Камера держит обоих бойцов в кадре (не пустой центр арены). */
export function MenuBgDuelViewport({
  arenaSize,
  leftHeadRef,
  rightHeadRef,
}: Props) {
  const render = useRender();
  const camRef = useRef({
    x: arenaSize / 2,
    y: arenaSize * 0.62,
  });

  useRenderEvent(
    "beforeRender",
    () => {
      const left = leftHeadRef.current;
      const right = rightHeadRef.current;
      const fallbackX = arenaSize / 2;
      const fallbackY = arenaSize * 0.62;
      const targetX =
        left && right
          ? (left.position.x + right.position.x) / 2
          : (left?.position.x ?? right?.position.x ?? fallbackX);
      const targetY =
        left && right
          ? (left.position.y + right.position.y) / 2
          : (left?.position.y ?? right?.position.y ?? fallbackY);

      const cam = camRef.current;
      cam.x += (targetX - cam.x) * 0.1;
      cam.y += (targetY - cam.y) * 0.1;

      // Чуть шире, если бойцы разлетелись.
      let span = 280;
      if (left && right) {
        span = Math.max(
          280,
          Math.abs(left.position.x - right.position.x) * 1.35,
          Math.abs(left.position.y - right.position.y) * 1.2,
        );
      }
      const camH = Math.min(arenaSize * 0.7, Math.max(420, span));

      const { canvas } = render;
      const aspect = canvas.width / Math.max(canvas.height, 1);
      const halfH = camH / 2;
      const halfW = halfH * aspect;

      const cx = Math.min(
        arenaSize - halfW - 20,
        Math.max(halfW + 20, cam.x),
      );
      const cy = Math.min(
        arenaSize - halfH - 20,
        Math.max(halfH + 20, cam.y),
      );

      const box = {
        min: { x: cx - halfW, y: cy - halfH },
        max: { x: cx + halfW, y: cy + halfH },
      };
      Matter.Render.lookAt(render, [box], Matter.Vector.create(0, 0), true);
    },
    [render, arenaSize, leftHeadRef, rightHeadRef],
  );

  return null;
}
