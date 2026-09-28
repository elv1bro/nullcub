import { MatterCollisionEventsPlugin } from "@1.framework/matter-collision-events";
import { Engine, Render, Runner } from "@1.framework/matter4react";
import { WorldComposite } from "@1.framework/matter4react/WorldComposite";
import debug from "debug";
import Matter from "matter-js";
import {
  useMemo,
  type ComponentProps,
  type PropsWithChildren,
} from "react";

//

Matter.Plugin.register(MatterCollisionEventsPlugin);
Matter.use(MatterCollisionEventsPlugin.name);

//

const log = debug("@:components:Renderer");

const DEFAULT_GRAVITY = { x: 0, y: 1 / 10, scale: 1 / 1_000 };

//

export function Renderer({
  children,
  engine = {},
  render = {},
  runner = {},
}: Props) {
  log("!");

  // Стабильные объекты: иначе useDeepCompareEffect в <Runner>/<Render>
  // пересоздаёт Matter loops и игра залипает около 30 FPS.
  const gx = engine.gravity?.x;
  const gy = engine.gravity?.y;
  const gs = engine.gravity?.scale;
  const constraintIterations = engine.constraintIterations;
  const positionIterations = engine.positionIterations;
  const velocityIterations = engine.velocityIterations;

  const engineOps: Matter.IEngineDefinition = useMemo(
    () => ({
      gravity: {
        x: gx ?? DEFAULT_GRAVITY.x,
        y: gy ?? DEFAULT_GRAVITY.y,
        scale: gs ?? DEFAULT_GRAVITY.scale,
      },
      // Чуть мягче дефолта 14/10 — меньше CPU на кадр, рэгдолл всё ещё держится.
      constraintIterations: constraintIterations ?? 12,
      positionIterations: positionIterations ?? 8,
      velocityIterations: velocityIterations ?? 6,
    }),
    [
      gx,
      gy,
      gs,
      constraintIterations,
      positionIterations,
      velocityIterations,
    ],
  );

  const bg = render.options?.background;
  const wireframes = render.options?.wireframes;
  const renderOps = useMemo(
    () =>
      ({
        options: {
          background: bg ?? "#111",
          wireframes: wireframes ?? false,
        },
      }) satisfies ComponentProps<typeof Render>["options"],
    [bg, wireframes],
  );

  const runnerEnabled = runner.enabled;
  const runnerDelta = runner.delta;
  const runnerMaxFrameTime = runner.maxFrameTime;
  const runnerOps: Matter.IRunnerOptions = useMemo(
    () => ({
      enabled: runnerEnabled ?? true,
      delta: runnerDelta ?? 1000 / 60,
      // Snapping к ближайшему 1Hz + дефолтный maxFrameTime=33ms ловили игру
      // в «яме» 30 FPS: один тяжёлый кадр → округление до 30 → дальше не вылезает.
      frameDeltaSnapping: false,
      frameDeltaSmoothing: false,
      maxFrameTime: runnerMaxFrameTime ?? 1000 / 20,
    }),
    [runnerEnabled, runnerDelta, runnerMaxFrameTime],
  );

  return (
    <Engine options={engineOps}>
      <Render options={renderOps}>
        <WorldComposite>{children}</WorldComposite>
      </Render>
      <Runner options={runnerOps} />
    </Engine>
  );
}

//

type Props = PropsWithChildren<{
  engine?: Matter.IEngineDefinition;
  render?: ComponentProps<typeof Render>["options"];
  runner?: Matter.IRunnerOptions;
}>;
