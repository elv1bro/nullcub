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
  const slots = [
    { x: arenaSize / 3, y: arenaSize / 2 },
    { x: (2 * arenaSize) / 3, y: arenaSize / 2 },
    { x: arenaSize / 4, y: arenaSize / 3 },
    { x: (3 * arenaSize) / 4, y: (2 * arenaSize) / 3 },
  ];

  return config.fighters.map((spec, i) => {
    const slot = slots[i % slots.length]!;
    return spawnFighter(spec, slot.x, slot.y, composites?.get(spec.id));
  });
}

export function rosterComposites(fighters: FighterRuntime[]): Composite[] {
  return fighters.map((f) => f.composite);
}

export function rosterBodies(fighters: FighterRuntime[]): Body[] {
  return fighters.flatMap((f) => f.composite.bodies);
}
