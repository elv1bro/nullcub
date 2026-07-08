import { Renderer } from "@/components/Renderer";
import { Viewport } from "@/components/Viewport";
import { FighterAIController } from "@/battle/FighterAIController";
import { spawnRoster, rosterBodies, rosterComposites } from "@/battle/spawnRoster";
import { useRosterHealth } from "@/battle/useRosterHealth";
import { useFighterMovement } from "@/battle/useFighterMovement";
import type { FighterRuntime } from "@/battle/types";
import { ARENA_ITEM_SPAWN_POSITIONS, DEFAULT_ARENA_ITEMS, spawnArenaItems } from "@/items";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { MAX_HP } from "@/lib/combat";
import { OPPONENT_COLORS, PLAYER_COLORS } from "@/lib/fighterColors";
import { getAiProfile } from "@/battle/aiProfiles";
import { Composite, SurroundingWalls } from "@1.framework/matter4react";
import Matter, { Body } from "matter-js";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type MutableRefObject,
} from "react";
import { usePlayerProfile } from "@/player/PlayerProfileContext";

export const SIZE = 1000;
const BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);

function FighterController({
  fighter,
  allFighters,
  disabledRef,
}: {
  fighter: FighterRuntime;
  allFighters: FighterRuntime[];
  disabledRef: MutableRefObject<boolean>;
}) {
  const headRef = useRef<Body | undefined>(fighter.head);
  headRef.current = fighter.head;

  const targetRef = useRef<Body | undefined>(undefined);
  const enemy = allFighters.find(
    (f) => f.id !== fighter.id && f.team !== fighter.team && f.hp > 0,
  );
  targetRef.current = enemy?.head;

  useFighterMovement(
    headRef,
    fighter.controller === "keyboard"
      ? "keyboard"
      : fighter.controller === "keyboard2"
        ? "keyboard2"
        : "none",
    disabledRef,
  );

  if (fighter.controller === "ai") {
    return (
      <FighterAIController
        headRef={headRef}
        targetRef={targetRef}
        disabledRef={disabledRef}
        bounds={BOUNDS}
        speedMult={fighter.aiSpeedMult ?? 1}
        profile={fighter.aiProfile ?? null}
      />
    );
  }
  return null;
}

export default function BattleLocal4FFA() {
  const { profile } = usePlayerProfile();
  const battleOverRef = useRef(false);
  const battleStartRef = useRef(0);
  const [fighters, setFighters] = useState<FighterRuntime[]>([]);
  const itemCompositesRef = useRef<Matter.Composite[]>([]);

  useEffect(() => {
    const roster = spawnRoster(
      {
        mode: "ffa",
        fighters: [
          {
            id: "p1",
            team: 0,
            name: profile.name,
            colors: profile.colors,
            controller: "keyboard",
            face: "webcam",
            isLocalHuman: true,
            maxHp: MAX_HP,
          },
          {
            id: "p2",
            team: 1,
            name: "Player 2",
            colors: { main: "#c084fc", secondary: "#7c3aed" },
            controller: "keyboard2",
            face: "synthetic",
            isLocalHuman: true,
            maxHp: MAX_HP,
          },
          {
            id: "bot1",
            team: 2,
            name: "Bot A",
            colors: OPPONENT_COLORS,
            controller: "ai",
            face: "synthetic",
            isLocalHuman: false,
            maxHp: MAX_HP,
            aiSpeedMult: getAiProfile("easy").speedMult,
            aiProfile: getAiProfile("easy"),
          },
          {
            id: "bot2",
            team: 3,
            name: "Bot B",
            colors: PLAYER_COLORS,
            controller: "ai",
            face: "synthetic",
            isLocalHuman: false,
            maxHp: MAX_HP,
            aiSpeedMult: getAiProfile("hard").speedMult,
            aiProfile: getAiProfile("hard"),
          },
        ],
      },
      SIZE,
    );
    itemCompositesRef.current = spawnArenaItems(
      DEFAULT_ARENA_ITEMS,
      [...ARENA_ITEM_SPAWN_POSITIONS],
    );
    setFighters(roster);
    battleStartRef.current = performance.now();
  }, [profile.name, profile.colors]);

  const composites = useMemo(
    () => [...rosterComposites(fighters), ...itemCompositesRef.current],
    [fighters],
  );

  const { fighters: live, battleOver, winnerId } = useRosterHealth(
    fighters,
    composites,
    battleStartRef,
    battleOverRef,
  );
  battleOverRef.current = battleOver;

  const protagonists = useMemo(() => rosterBodies(live), [live]);

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center">
      <Renderer engine={{ gravity: BATTLE_GRAVITY }}>
        {battleOver && winnerId && (
          <div className="fixed top-4 left-1/2 -translate-x-1/2 z-30 text-xl font-black text-amber-300">
            Winner: {live.find((f) => f.id === winnerId)?.name}
          </div>
        )}
        <Viewport protagonists={protagonists} />
        <SurroundingWalls thick={SIZE} bounds={BOUNDS} options={{ render: { fillStyle: "#333" } }} />
        {live.map((f) => (
          <Composite.add key={f.composite.id} object={f.composite} />
        ))}
        {itemCompositesRef.current.map((item) => (
          <Composite.add key={item.id} object={item} />
        ))}
        {live.map((f) => (
          <FighterController
            key={f.id}
            fighter={f}
            allFighters={live}
            disabledRef={battleOverRef}
          />
        ))}
      </Renderer>
    </section>
  );
}
