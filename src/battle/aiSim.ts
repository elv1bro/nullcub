import Matter, { Body, Vector, type Bounds } from "matter-js";
import {
  computeBotMoveIntent,
  createBotBrainState,
  type BotBrainState,
} from "./aiLogic";
import type { AiProfile } from "./aiProfiles";
import { AI_PROFILES, getAiProfile } from "./aiProfiles";

const ARENA = 1000;
const BOUNDS: Bounds = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: ARENA, y: ARENA },
]);

/** Упрощённый «средний игрок» — чуть слабее бота normal для калибровки. */
export const AVERAGE_PLAYER_PROXY: AiProfile = {
  ...getAiProfile("normal"),
  id: "normal",
  speedMult: 0.92,
  reactionDelayMs: 240,
  mistakeRate: 0.12,
  aimNoise: 0.14,
  lungeCooldownMs: 1100,
  grabRange: 0,
  grabChance: 0,
  useDash: false,
  useFlip: false,
  useBrace: false,
};

export interface SimFighter {
  head: Body;
  hp: number;
  damageDealt: number;
  brain: BotBrainState;
}

export interface SimDuelResult {
  botWins: number;
  playerWins: number;
  draws: number;
  botWinRate: number;
}

function makeHead(x: number, y: number): Body {
  return Matter.Bodies.circle(x, y, 18, {
    label: "Head",
    frictionAir: 0.02,
    restitution: 0.2,
  });
}

function tickFighter(
  profile: AiProfile,
  self: SimFighter,
  enemy: SimFighter,
  now: number,
  dt: number,
): void {
  const intent = computeBotMoveIntent(
    profile,
    self.brain,
    self.head,
    enemy.head,
    BOUNDS,
    now,
  );
  const targetVel = Vector.mult(intent.worldMove, intent.speed * dt * 4.2);
  Matter.Body.setVelocity(
    self.head,
    Vector.add(Vector.mult(self.head.velocity, 0.92), targetVel),
  );
}

function headImpactDamage(a: Body, b: Body): number {
  const rel = Vector.magnitude(Vector.sub(a.velocity, b.velocity));
  const dist = Vector.magnitude(Vector.sub(a.position, b.position));
  if (dist > 38) return 0;
  return Math.max(0, rel * 28 + (38 - dist) * 0.35);
}

export function simulateDuel(
  botProfile: AiProfile,
  playerProfile: AiProfile = AVERAGE_PLAYER_PROXY,
  rounds = 200,
  maxTicks = 2400,
  seed = 42,
): SimDuelResult {
  let botWins = 0;
  let playerWins = 0;
  let draws = 0;
  let rng = seed;

  const rand = () => {
    rng = (rng * 1664525 + 1013904223) >>> 0;
    return rng / 0x1_0000_0000;
  };

  const nativeRandom = Math.random;
  Math.random = rand;

  try {
    for (let r = 0; r < rounds; r++) {
      rng = seed + r * 7919;
      const bot: SimFighter = {
        head: makeHead(ARENA * 0.62, ARENA * 0.5),
        hp: 100,
        damageDealt: 0,
        brain: createBotBrainState(),
      };
      const player: SimFighter = {
        head: makeHead(ARENA * 0.38, ARENA * 0.5),
        hp: 100,
        damageDealt: 0,
        brain: createBotBrainState(),
      };

      let t = 0;
      const start = r * maxTicks;
      while (t < maxTicks && bot.hp > 0 && player.hp > 0) {
        const now = start + t * 16;
        const dt = 1 / 60;
        tickFighter(botProfile, bot, player, now, dt);
        tickFighter(playerProfile, player, bot, now, dt);

        for (const body of [bot.head, player.head]) {
          if (body.position.x < 20) Matter.Body.setPosition(body, { x: 20, y: body.position.y });
          if (body.position.x > ARENA - 20) {
            Matter.Body.setPosition(body, { x: ARENA - 20, y: body.position.y });
          }
          if (body.position.y < 20) Matter.Body.setPosition(body, { x: body.position.x, y: 20 });
          if (body.position.y > ARENA - 20) {
            Matter.Body.setPosition(body, { x: body.position.x, y: ARENA - 20 });
          }
        }

        const dmgToPlayer = headImpactDamage(bot.head, player.head);
        const dmgToBot = headImpactDamage(player.head, bot.head);
        player.hp -= dmgToPlayer;
        bot.hp -= dmgToBot;
        bot.damageDealt += dmgToPlayer;
        player.damageDealt += dmgToBot;
        t++;
      }

      if (bot.hp > player.hp) botWins++;
      else if (player.hp > bot.hp) playerWins++;
      else if (bot.damageDealt > player.damageDealt) botWins++;
      else if (player.damageDealt > bot.damageDealt) playerWins++;
      else draws++;
    }
  } finally {
    Math.random = nativeRandom;
  }

  return {
    botWins,
    playerWins,
    draws,
    botWinRate: botWins / rounds,
  };
}

export function summarizePresetWinRates(
  rounds = 120,
): Record<string, { target: number; simulated: number }> {
  const out: Record<string, { target: number; simulated: number }> = {};
  for (const id of Object.keys(AI_PROFILES) as (keyof typeof AI_PROFILES)[]) {
    const profile = AI_PROFILES[id];
    const { botWinRate } = simulateDuel(profile, AVERAGE_PLAYER_PROXY, rounds);
    out[id] = { target: profile.targetBotWinRate, simulated: botWinRate };
  }
  return out;
}
