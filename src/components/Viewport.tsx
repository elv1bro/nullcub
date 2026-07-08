//

import { useRender, useRenderEvent } from "@1.framework/matter4react";
import debug from "debug";
import Matter, { Body, Vector } from "matter-js";
import { type RefObject, useLayoutEffect } from "react";
import { useEvent } from "react-use";
import {
  applyCameraShake,
  applyFinisherCam,
  sampleShake,
  type HitEffectStore,
} from "@/lib/hitEffects";

//

const log = debug("@1.framework:matter4react:Viewport");

//

const padding = Vector.create(90, 90);
export function Viewport({
  extents: _extents,
  protagonists,
  hitEffectsStore,
}: Props) {
  log("!");
  const render = useRender();

  const resize = () => {
    const [width, height] = [window.innerWidth, window.innerHeight];
    // TODO(douglasduteil): remove this when Render.setSize is released
    // https://github.com/liabru/matter-js/commit/fc0583975d07f74a7c45e7a84bd3a94b3a2068be
    render.options.width = width;
    render.options.height = height;

    render.canvas.width = width;
    render.canvas.height = height;
  };
  useEvent("resize", resize);
  useLayoutEffect(resize, [render]);

  useRenderEvent(
    "beforeRender",
    () => {
      const store = hitEffectsStore?.current;
      const now = performance.now();
      const finisherActive =
        store?.finisher && now < store.finisher.until;

      if (!finisherActive) {
        Matter.Render.lookAt(render, protagonists, padding, true);
      } else if (store) {
        Matter.Render.lookAt(render, protagonists, padding, true);
        applyFinisherCam(render, store, now);
      }

      if (store) {
        const shake = sampleShake(store, now);
        applyCameraShake(render, shake.dx, shake.dy);
      }
    },
    [render, protagonists, hitEffectsStore],
  );
  return null;
}

//

type Props = {
  extents?: { min: Vector; max: Vector };
  protagonists: Body[];
  hitEffectsStore?: RefObject<HitEffectStore | null>;
};
