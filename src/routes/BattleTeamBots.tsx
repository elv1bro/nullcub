import { BattleSpaceBg } from "@/components/BattleSpaceBg";
import { Renderer } from "@/components/Renderer";
import { Viewport } from "@/components/Viewport";
import { FighterAIController } from "@/battle/FighterAIController";
import { RosterBattleOverlay } from "@/battle/RosterBattleOverlay";
import { spawnRoster, rosterBodies, rosterComposites } from "@/battle/spawnRoster";
import { useRosterHealth } from "@/battle/useRosterHealth";
import { useFighterMovement } from "@/battle/useFighterMovement";
import type { FighterRuntime } from "@/battle/types";
import { getAiProfile, type AiDifficultyId } from "@/battle/aiProfiles";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { getBattleConfig } from "@/lib/battleConfig";
import { MAX_HP } from "@/lib/combat";
import { OPPONENT_COLORS } from "@/lib/fighterColors";
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

const HUMAN_PALETTE = [
  { main: "#f5c542", secondary: "#f59e0b" },
  { main: "#3dd68c", secondary: "#10b981" },
  { main: "#ff6b4a", secondary: "#ef4444" },
  { main: "#5ec8ff", secondary: "#38bdf8" },
] as const;

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

/**
 * Пати (команда 0) против ботов (команда 1).
 * Локально управляются первые двое (WASD / стрелки); остальные люди — AI-союзники.
 */
export default function BattleTeamBots() {
  const { profile } = usePlayerProfile();
  const config = getBattleConfig();
  const teamCfg =
    config.kind === "teamBots"
      ? config
      : {
          humans: 1,
          humanNames: [profile.name],
          bots: 1,
          difficulty: "normal" as AiDifficultyId,
        };

  const battleOverRef = useRef(false);
  const battleStartRef = useRef(0);
  const [fighters, setFighters] = useState<FighterRuntime[]>([]);
  const itemCompositesRef = useRef<Matter.Composite[]>([]);

  useEffect(() => {
    const humans = Math.max(1, Math.min(4, teamCfg.humans));
    const bots = Math.max(1, Math.min(3, teamCfg.bots));
    const diff = teamCfg.difficulty as AiDifficultyId;
    const ai = getAiProfile(diff);

    const humanSpecs = Array.from({ length: humans }, (_, i) => {
      const name =
        teamCfg.humanNames[i] ||
        (i === 0 ? profile.name : `P${i + 1}`);
      const controller: FighterRuntime["controller"] =
        i === 0 ? "keyboard" : i === 1 ? "keyboard2" : "ai";
      const face: FighterRuntime["face"] =
        i === 0 ? "webcam" : "synthetic";
      return {
        id: `p${i + 1}`,
        team: 0,
        name,
        colors: HUMAN_PALETTE[i] ?? HUMAN_PALETTE[0]!,
        controller,
        face,
        isLocalHuman: controller !== "ai",
        maxHp: MAX_HP,
        ...(controller === "ai"
          ? {
              aiSpeedMult: ai.speedMult * 0.9,
              aiProfile: ai,
            }
          : {}),
      };
    });

    const botSpecs = Array.from({ length: bots }, (_, i) => ({
      id: `bot${i + 1}`,
      team: 1,
      name: bots === 1 ? "Boss Bot" : `Bot ${i + 1}`,
      colors: OPPONENT_COLORS,
      controller: "ai" as const,
      face: "synthetic" as const,
      isLocalHuman: false,
      // 4v1: один бот должен выдерживать пати
      maxHp: Math.round(MAX_HP * (bots === 1 ? 2.2 : 1.15)),
      aiSpeedMult: ai.speedMult * (bots === 1 ? 1.15 : 1),
      aiProfile: ai,
    }));

    const roster = spawnRoster(
      { mode: "coop", fighters: [...humanSpecs, ...botSpecs] },
      SIZE,
    );
    itemCompositesRef.current = spawnArenaItems(DEFAULT_ARENA_ITEMS, [
      ...ARENA_ITEM_SPAWN_POSITIONS,
    ]);
    setFighters(roster);
    battleStartRef.current = performance.now();
  }, [
    profile.name,
    teamCfg.humans,
    teamCfg.bots,
    teamCfg.difficulty,
    teamCfg.humanNames.join("|"),
  ]);

  const composites = useMemo(
    () => [...rosterComposites(fighters), ...itemCompositesRef.current],
    [fighters],
  );

  const { fighters: live, battleOver, winnerId } = useRosterHealth(
    fighters,
    composites,
    battleStartRef,
    battleOverRef,
    "coop",
  );
  battleOverRef.current = battleOver;

  const protagonists = useMemo(() => rosterBodies(live), [live]);
  const winnerTeam =
    winnerId != null
      ? (live.find((f) => f.id === winnerId)?.team ?? null)
      : null;

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center">
      <Renderer engine={{ gravity: BATTLE_GRAVITY }}>
        {battleOver && (
          <div className="fixed top-4 left-1/2 -translate-x-1/2 z-30 px-4 py-2 rounded-xl border-2 border-black bg-amber-300 text-black font-black uppercase tracking-wide shadow-[4px_4px_0_#000]">
            {winnerTeam === 0 ? "Party wins!" : "Bots win…"}
          </div>
        )}
        <BattleSpaceBg />
        <Viewport protagonists={protagonists} />
        <SurroundingWalls
          thick={SIZE}
          bounds={BOUNDS}
          options={{ render: { fillStyle: "#1c2430" } }}
        />
        {live.map((f) => (
          <Composite.add key={f.composite.id} object={f.composite} />
        ))}
        {itemCompositesRef.current.map((item) => (
          <Composite.add key={item.id} object={item} />
        ))}
        {live.length > 0 && <RosterBattleOverlay fighters={live} />}
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
