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
import { applyRenderSize } from "@/render/setRenderPixelRatio";

//

const log = debug("@1.framework:matter4react:Viewport");

//

const paddingNormal = Vector.create(90, 90);
const paddingSudden = Vector.create(48, 48);
export function Viewport({
  extents: _extents,
  protagonists,
  hitEffectsStore,
  suddenDeath = false,
}: Props) {
  log("!");
  const render = useRender();

  const resize = () => {
    // CSS size + DPR: иначе на телефоне canvas 1× растягивается → «мыло».
    applyRenderSize(render, window.innerWidth, window.innerHeight);
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
      const pad = suddenDeath ? paddingSudden : paddingNormal;

      Matter.Render.lookAt(render, protagonists, pad, true);
      if (store) {
        if (finisherActive) applyFinisherCam(render, store, now);
        const shake = sampleShake(store, now);
        applyCameraShake(render, shake.dx, shake.dy);
      }
    },
    [render, protagonists, hitEffectsStore, suddenDeath],
  );
  return null;
}

//

type Props = {
  extents?: { min: Vector; max: Vector };
  protagonists: Body[];
  hitEffectsStore?: RefObject<HitEffectStore | null>;
  /** Sudden death — камера ближе, «арена сужается». */
  suddenDeath?: boolean;
};
