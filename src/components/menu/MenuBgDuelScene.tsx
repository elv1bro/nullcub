import { getAiProfile } from "@/battle/aiProfiles";
import { useBattleSession, type CoreFighterSpec } from "@/core";
import { MAX_HP } from "@/lib/combat";
import { BATTLE_SPAWN_SPREAD } from "@/lib/battleTuning";
import { tagStickmanHands } from "@/lib/grab/hands";
import { applyPlayerColors } from "@/lib/paintStickman";
import { useSettings } from "@/settings/SettingsContext";
import { createStickman } from "@/utils/createStickman";
import {
  Composite,
  Rectangle,
  SurroundingWalls,
  useEngine,
} from "@1.framework/matter4react";
import Matter, { Body, type Body as MatterBody, type Composite as MatterComposite } from "matter-js";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { MenuBgDuelHud } from "./MenuBgDuelHud";
import { MenuBgDuelViewport } from "./MenuBgDuelViewport";

const ARENA = 1000;
/** Ближе к полу — не «летят» с середины карты. */
const SPAWN_Y = ARENA - 260;
const REMATCH_MS = 1800;

/** Всегда один контраст: синий vs красный — сразу ясно кто кто. */
const LEFT_COLORS = { main: "#38bdf8", secondary: "#0ea5e9" };
const RIGHT_COLORS = { main: "#f87171", secondary: "#ef4444" };

function spawnBgFighter(
  id: "player" | "opponent",
  x: number,
  y: number,
  main: string,
  secondary: string,
): { composite: MatterComposite; head: MatterBody; spec: CoreFighterSpec } {
  const composite = createStickman(x, y, {
    render: { fillStyle: main },
  });
  applyPlayerColors(composite, main, secondary);
  tagStickmanHands(composite, id);
  const head = composite.bodies.find((b) => b.label === "Head");
  if (!head) throw new Error("menu bg duel: missing head");
  head.render.visible = true;
  head.render.fillStyle = secondary;
  head.render.strokeStyle = "#ffffff";
  head.render.lineWidth = 3;
  for (const body of composite.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }
  // Только easy — фон должен быть читаемой дракой, не цирком.
  return {
    composite,
    head,
    spec: {
      id,
      composite,
      head,
      maxHp: MAX_HP,
      aiProfile: getAiProfile("easy"),
    },
  };
}

function MenuBgDuelRound({ onFinished }: { onFinished: () => void }) {
  const engine = useEngine();
  const { settings } = useSettings();
  const leftHeadRef = useRef<MatterBody>();
  const rightHeadRef = useRef<MatterBody>();
  const leftLabel = settings.language === "ru" ? "СИНИЙ" : "BLUE";
  const rightLabel = settings.language === "ru" ? "КРАСНЫЙ" : "RED";

  const spawn = useMemo(() => {
    const center = ARENA / 2;
    // Чуть ближе друг к другу — сразу контакт, меньше беготни.
    const spread = Math.round(BATTLE_SPAWN_SPREAD * 0.85);
    const left = spawnBgFighter(
      "player",
      center - spread,
      SPAWN_Y,
      LEFT_COLORS.main,
      LEFT_COLORS.secondary,
    );
    const right = spawnBgFighter(
      "opponent",
      center + spread,
      SPAWN_Y,
      RIGHT_COLORS.main,
      RIGHT_COLORS.secondary,
    );
    leftHeadRef.current = left.head;
    rightHeadRef.current = right.head;
    return { left, right };
  }, []);

  const fighters = useMemo(
    () => [spawn.left.spec, spawn.right.spec],
    [spawn],
  );

  const { battleOver, playerHp, opponentHp } = useBattleSession({
    enabled: Boolean(engine),
    arenaSize: ARENA,
    fighters,
    playerCompositeId: spawn.left.composite.id,
    opponentCompositeId: spawn.right.composite.id,
    externalRunner: true,
    settleTicksBeforeBegin: 45,
    battleStartMs: performance.now(),
  });

  useEffect(() => {
    if (!battleOver) return;
    const t = window.setTimeout(onFinished, REMATCH_MS);
    return () => window.clearTimeout(t);
  }, [battleOver, onFinished]);

  const bounds = useMemo(
    () =>
      Matter.Bounds.create([
        { x: 0, y: 0 },
        { x: ARENA, y: ARENA },
      ]),
    [],
  );

  return (
    <>
      <MenuBgDuelViewport
        arenaSize={ARENA}
        leftHeadRef={leftHeadRef}
        rightHeadRef={rightHeadRef}
      />
      <MenuBgDuelHud
        leftHeadRef={leftHeadRef}
        rightHeadRef={rightHeadRef}
        leftHp={playerHp}
        rightHp={opponentHp}
        leftColor={LEFT_COLORS.main}
        rightColor={RIGHT_COLORS.main}
        leftLabel={leftLabel}
        rightLabel={rightLabel}
        battleOver={battleOver}
      />
      <SurroundingWalls
        thick={80}
        bounds={bounds}
        options={{ render: { fillStyle: "#14141c", visible: false } }}
      />
      {/* Визуальный пол — якорь «это арена», не космос. */}
      <Rectangle
        x={ARENA / 2}
        y={ARENA - 18}
        width={ARENA - 40}
        height={36}
        options={{
          isStatic: true,
          label: "MenuBgFloor",
          render: {
            fillStyle: "#1a1a28",
            strokeStyle: "rgba(255,255,255,0.08)",
            lineWidth: 2,
            visible: true,
          },
        }}
      />
      <Composite.add object={spawn.left.composite} />
      <Composite.add object={spawn.right.composite} />
    </>
  );
}

/** Фоновый AI vs AI: контрастные бойцы у пола, камера на драке. */
export function MenuBgDuelScene() {
  const [duelKey, setDuelKey] = useState(0);
  const rematch = useCallback(() => {
    setDuelKey((k) => k + 1);
  }, []);

  return <MenuBgDuelRound key={duelKey} onFinished={rematch} />;
}
