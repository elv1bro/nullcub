import { useRender, useRenderEvent } from "@1.framework/matter4react";
import Matter from "matter-js";
import { MENU_ARENA_H, MENU_ARENA_W } from "@/lib/menuArenaConstants";

const CAM_CX = MENU_ARENA_W * 0.28;
const CAM_CY = MENU_ARENA_H * 0.52;
/** Высота видимой зоны в world-units. */
const CAM_H = 560;

/** Фиксированная камера меню — lookAt включает hasBounds, иначе тело и лицо рисуются в разных местах. */
export function MenuArenaViewport() {
  const render = useRender();

  useRenderEvent(
    "beforeRender",
    () => {
      const { canvas } = render;
      const aspect = canvas.width / canvas.height;
      const halfH = CAM_H / 2;
      const halfW = halfH * aspect;

      const box = {
        min: { x: CAM_CX - halfW, y: CAM_CY - halfH },
        max: { x: CAM_CX + halfW, y: CAM_CY + halfH },
      };

      Matter.Render.lookAt(render, [box], Matter.Vector.create(0, 0), true);
    },
    [render],
  );

  return null;
}
