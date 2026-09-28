import Matter from "matter-js";
import { createBattleSession } from "@/core";
import { getAiProfile } from "@/battle/aiProfiles";
import { MAX_HP } from "@/lib/combat";
import { createStickman } from "@/utils/createStickman";
import { buildMonster, settleComposite } from "./buildMonster";
import { normalizeMonsterDef, type MonsterDef } from "./monsterTypes";
import { STARTER_MONSTERS } from "./starterMonsters";

export type LinkIntegrityResult = {
  name: string;
  ok: boolean;
  broken: string[];
};

/** Макс. доп. зазор поверх сумм радиусов — выше = «развалился». */
export const LINK_INTEGRITY_SLACK_PX = 95;

export function maxLinkDistance(
  def: MonsterDef,
  composite: Matter.Composite,
): { link: string; dist: number; max: number; ok: boolean }[] {
  return def.links.map((link) => {
    const a = composite.bodies[link.a]!;
    const b = composite.bodies[link.b]!;
    const dist = Matter.Vector.magnitude(
      Matter.Vector.sub(a.position, b.position),
    );
    const max =
      (a.circleRadius ?? 10) + (b.circleRadius ?? 10) + LINK_INTEGRITY_SLACK_PX;
    return {
      link: `${link.type ?? "rigid"} ${link.a}-${link.b}`,
      dist,
      max,
      ok: dist < max,
    };
  });
}

/** Headless: монстр vs stickman, hard AI, N тиков — связи не рвутся. */
export function runMonsterIntegrityFight(
  raw: MonsterDef,
  ticks = 360,
): LinkIntegrityResult {
  const def = normalizeMonsterDef(raw);
  const player = createStickman(280, 520, { render: { visible: false } });
  const built = buildMonster(def, 720, 520);
  if (!built?.head) {
    return { name: def.name, ok: false, broken: ["build failed"] };
  }
  settleComposite(built.composite);

  const session = createBattleSession({
    arenaSize: 1000,
    fighters: [
      {
        id: "player",
        composite: player,
        head: player.bodies.find((b) => b.label === "Head")!,
        maxHp: MAX_HP,
      },
      {
        id: "bot",
        composite: built.composite,
        head: built.head,
        maxHp: Math.max(200, built.maxHp),
        aiProfile: getAiProfile("hard"),
      },
    ],
    playerCompositeId: player.id,
    opponentCompositeId: built.composite.id,
    itemComposites: [],
  });
  session.beginBattle();
  for (let i = 0; i < ticks; i++) session.tick(1000 / 60);

  const distances = maxLinkDistance(def, built.composite);
  const broken = distances.filter((d) => !d.ok).map((d) => d.link);
  session.destroy();
  return { name: def.name, ok: broken.length === 0, broken };
}

export function runStarterIntegritySuite(ticks = 360): LinkIntegrityResult[] {
  return STARTER_MONSTERS.map((template, index) =>
    runMonsterIntegrityFight(
      {
        ...template,
        id: `starter-${index}`,
        createdAt: 0,
      },
      ticks,
    ),
  );
}

/** Детерминированный LCG — stress не должен флакать в CI. */
function makeRng(seed: number): () => number {
  let s = seed >>> 0 || 1;
  return () => {
    s = (Math.imul(1664525, s) + 1013904223) >>> 0;
    return s / 0x100000000;
  };
}

/**
 * Короткая тряска на клоне монстра (не трогает холст мастерской).
 * ok=false → связи разъехались — не Ready к бою.
 */
export function stressTestMonsterDef(
  raw: MonsterDef,
  steps = 90,
  seed = 42,
): { ok: boolean; broken: string[] } {
  const def = normalizeMonsterDef(raw);
  const built = buildMonster(def, 500, 400);
  if (!built) return { ok: false, broken: ["build failed"] };

  const rand = makeRng(seed);
  const engine = Matter.Engine.create({
    gravity: { x: 0, y: 1 / 20, scale: 1 / 1000 },
  });
  Matter.World.add(engine.world, built.composite);

  for (const body of built.composite.bodies) {
    Matter.Body.setVelocity(body, {
      x: (rand() - 0.5) * 16,
      y: (rand() - 0.5) * 10,
    });
  }

  for (let i = 0; i < steps; i++) {
    if (i % 18 === 0) {
      const body = built.composite.bodies[i % built.composite.bodies.length];
      if (body) {
        Matter.Body.applyForce(body, body.position, {
          x: (rand() - 0.5) * 0.07,
          y: -0.035,
        });
      }
    }
    Matter.Engine.update(engine, 1000 / 60);
  }

  const distances = maxLinkDistance(def, built.composite);
  const broken = distances.filter((d) => !d.ok).map((d) => d.link);
  Matter.World.clear(engine.world, false);
  Matter.Engine.clear(engine);
  return { ok: broken.length === 0, broken };
}
