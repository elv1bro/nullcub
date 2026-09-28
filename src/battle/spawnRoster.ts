import { createStickman } from "@/utils/createStickman";
import { tagStickmanHands } from "@/lib/grab/hands";
import { applyPlayerColors } from "@/lib/paintStickman";
import { Body, type Composite } from "matter-js";
import type { FighterRuntime, RosterBattleConfig } from "./types";
import { MAX_HP } from "@/lib/combat";

export function spawnFighter(
  spec: RosterBattleConfig["fighters"][number],
  x: number,
  y: number,
  composite?: Composite,
): FighterRuntime {
  const stickman =
    composite ??
    createStickman(x, y, {
      render: { fillStyle: spec.colors.main },
    });

  if (!composite) {
    applyPlayerColors(stickman, spec.colors.main, spec.colors.secondary);
  }

  tagStickmanHands(stickman, spec.id);

  const head = stickman.bodies.find((b) => b.label === "Head");
  if (head) head.render.visible = false;

  for (const body of stickman.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }

  return {
    ...spec,
    composite: stickman,
    head: head!,
    hp: spec.maxHp ?? MAX_HP,
    maxHp: spec.maxHp ?? MAX_HP,
  };
}

export function spawnRoster(
  config: RosterBattleConfig,
  arenaSize: number,
  composites?: Map<string, Composite>,
): FighterRuntime[] {
  const ffaSlots = [
    { x: arenaSize / 3, y: arenaSize / 2 },
    { x: (2 * arenaSize) / 3, y: arenaSize / 2 },
    { x: arenaSize / 4, y: arenaSize / 3 },
    { x: (3 * arenaSize) / 4, y: (2 * arenaSize) / 3 },
  ];

  if (config.mode === "coop" || config.mode === "teams") {
    const byTeam = new Map<number, typeof config.fighters>();
    for (const spec of config.fighters) {
      const list = byTeam.get(spec.team) ?? [];
      list.push(spec);
      byTeam.set(spec.team, list);
    }
    const teams = [...byTeam.keys()].sort((a, b) => a - b);
    const out: FighterRuntime[] = [];
    for (let ti = 0; ti < teams.length; ti++) {
      const team = teams[ti]!;
      const members = byTeam.get(team)!;
      const side = teams.length <= 1 ? 0.5 : ti === 0 ? 0.28 : 0.72;
      for (let i = 0; i < members.length; i++) {
        const spec = members[i]!;
        const spread = (i - (members.length - 1) / 2) * (arenaSize * 0.08);
        const y = arenaSize * 0.42 + spread;
        out.push(
          spawnFighter(
            spec,
            arenaSize * side,
            y,
            composites?.get(spec.id),
          ),
        );
      }
    }
    return out;
  }

  return config.fighters.map((spec, i) => {
    const slot = ffaSlots[i % ffaSlots.length]!;
    return spawnFighter(spec, slot.x, slot.y, composites?.get(spec.id));
  });
}

export function rosterComposites(fighters: FighterRuntime[]): Composite[] {
  return fighters.map((f) => f.composite);
}

export function rosterBodies(fighters: FighterRuntime[]): Body[] {
  return fighters.flatMap((f) => f.composite.bodies);
}
