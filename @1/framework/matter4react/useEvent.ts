//

import debug from "debug";
import { Events } from "matter-js";
import { useEffect, type DependencyList } from "react";
import { useEngine } from "./EngineContext";
import { useRender } from "./RenderContext";

//

const log = debug("@1.framework:matter4react:useEvent");

//

type Params = Parameters<typeof Events.on>;
// Callback шире, чем последняя перегрузка Events.on: конкретные хуки
// (useEventAfterUpdate и т.п.) сами задают точный тип события.
type AnyEventCallback = (e: never) => void;

export function useEvent(
  obj: Params[0] | null,
  name: Params[1],
  callback: AnyEventCallback,
  deps?: DependencyList
) {
  useEffect(() => {
    log("+ useEffect", { obj, name, deps });
    if (!obj) return;
    log("+ useEffect", { obj, name });
    Events.on(obj, name, callback as Params[2]);
    return () => Events.off(obj, name, callback as Params[2]);
  }, deps);
}

export function useEngineEvent(
  name: Params[1],
  callback: AnyEventCallback,
  deps?: DependencyList
) {
  const engine = useEngine();
  useEvent(engine, name, callback, [engine?.world?.id ?? null, ...(deps ?? [])]);
}

export function useRenderEvent(
  name: Params[1],
  callback: AnyEventCallback,
  deps?: DependencyList
) {
  const render = useRender();
  useEvent(render, name, callback, [render, ...(deps ?? [])]);
}
