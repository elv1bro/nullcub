import { BattleSpaceBg } from "@/components/BattleSpaceBg";
import { FullscreenToggle } from "@/components/FullscreenToggle";
import { Renderer } from "@/components/Renderer";
import { Viewport } from "@/components/Viewport";
import { GameContext } from "@/GameContext";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  spawnArenaItems,
} from "@/items";
import { getBattleConfig } from "@/lib/battleConfig";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { useTranslation } from "@/settings/SettingsContext";
import {
  Composite,
  SurroundingWalls,
  useEngine,
  useRender,
} from "@1.framework/matter4react";
import Matter, { Body } from "matter-js";
import {
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { useKeyPressEvent } from "react-use";

const SIZE = 1000;
const BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);

/** Плотнее сетка спавна — без бойцов можно разложить больше стволов. */
const SANDBOX_SPAWNS = [
  ...ARENA_ITEM_SPAWN_POSITIONS,
  { x: 350, y: 220 },
  { x: 650, y: 220 },
  { x: 500, y: 380 },
  { x: 500, y: 620 },
];

function WeaponMouseDrag() {
  const engine = useEngine();
  const render = useRender();

  useEffect(() => {
    const canvas = render.canvas;
    if (!canvas) return;

    const mouse = Matter.Mouse.create(canvas);
    mouse.pixelRatio = window.devicePixelRatio || 1;
    const mouseConstraint = Matter.MouseConstraint.create(engine, {
      mouse,
      constraint: {
        stiffness: 0.2,
        damping: 0.1,
        render: { visible: false },
      },
    });
    Matter.Composite.add(engine.world, mouseConstraint);

    const sync = () => {
      mouse.element = canvas;
      mouse.pixelRatio = window.devicePixelRatio || 1;
    };
    sync();
    window.addEventListener("resize", sync);

    return () => {
      window.removeEventListener("resize", sync);
      Matter.Composite.remove(engine.world, mouseConstraint);
      // Matter.Mouse не имеет destroy в типах — обнуляем element.
      (mouse as { element?: HTMLElement | null }).element = null;
    };
  }, [engine, render]);

  return null;
}

function WeaponSandboxScene() {
  const config = getBattleConfig();
  const ids =
    config.kind === "weaponSandbox"
      ? config.arenaItemIds
      : ["sword", "taser", "frying-pan", "bat"];

  const [items, setItems] = useState<Matter.Composite[]>([]);
  const [protagonists, setProtagonists] = useState<Body[]>([]);

  useEffect(() => {
    const spawned = spawnArenaItems(ids, [...SANDBOX_SPAWNS]);
    for (const item of spawned) {
      for (const body of item.bodies) {
        Body.setVelocity(body, { x: 0, y: 0 });
        Body.setAngularVelocity(body, 0);
      }
    }
    setItems(spawned);
    setProtagonists(spawned.flatMap((c) => c.bodies));
  }, [ids.join("|")]);

  return (
    <>
      <BattleSpaceBg />
      <Viewport protagonists={protagonists} />
      <SurroundingWalls
        thick={SIZE}
        bounds={BOUNDS}
        options={{ render: { fillStyle: "#1c2430" } }}
      />
      {items.map((item) => (
        <Composite.add key={item.id} object={item} />
      ))}
      <WeaponMouseDrag />
    </>
  );
}

/**
 * Арена только с оружием: смотреть физику/форму, таскать мышью.
 */
export default function BattleWeaponSandbox() {
  const { sendN } = useContext(GameContext);
  const t = useTranslation();

  useKeyPressEvent("Escape", () => sendN("BACK")());

  const hint = useMemo(() => t.lab.sandboxDragHint, [t]);

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center relative">
      <FullscreenToggle visible />
      <div className="fixed top-3 left-1/2 -translate-x-1/2 z-30 px-3 py-1.5 rounded-lg border border-white/20 bg-black/55 text-amber-100 text-sm font-ui pointer-events-none">
        {hint}
      </div>
      <button
        type="button"
        className="fixed top-3 right-3 z-30 px-3 py-1.5 rounded-lg border border-white/25 bg-black/60 text-white text-sm font-ui"
        onClick={() => sendN("BACK")()}
      >
        {t.menu.back}
      </button>
      <Renderer engine={{ gravity: BATTLE_GRAVITY }}>
        <WeaponSandboxScene />
      </Renderer>
    </section>
  );
}
