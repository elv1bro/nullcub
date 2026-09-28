import Matter, { Body, Vector, type Composite } from "matter-js";
import {
  computeDamage,
  FIGHTER_HIT_COOLDOWN_MS,
  BOT_DAMAGE_MULTIPLIER,
} from "@/lib/combat";
import { computeKnockback } from "@/lib/knockback";
import { resolveHitParties, type CombatFxConfig } from "@/lib/combatFx";
import { isSaveBody } from "@/lib/isSaveBody";
import { isBattleSpawnGrace } from "@/lib/combatGrace";
import {
  canFightersTradeDamage,
  filterDamageFromDeadAggressors,
} from "@/lib/combatActive";
import {
  filterGrabDamage,
  isGrabbingFighter,
  type GrabDamageContext,
} from "@/lib/grab/rules";
import { getDamageType } from "@/items/damageTypes";
import { computeDisarmChance, rollDisarm } from "@/items/disarm";
import { filterFriendlyWeaponDamage } from "@/items/resolveWeaponHit";
import { items } from "@/items/registry";
import { isKnockoutFromLethalHit } from "@/lib/knockoutDetect";
import { moveBody } from "@/lib/moveBody";
import { KNOCKBACK_SPEED, BRACE_KNOCKBACK_MULT } from "@/lib/battleTuning";
import { clampBodySpeed } from "@/lib/bodySpeed";
import type { BattleEventBus } from "./events";
import type { GrabController } from "./grabController";
import type { CoreFighterRuntime } from "./types";

export interface ImpactEntry {
  body: Body;
  strength: number;
  vec: Vector;
}

export interface CombatPipelineState {
  pairCooldown: Map<string, number>;
  impacts: ImpactEntry[];
  knockoutDispatched: Set<number>;
}

export function createCombatPipelineState(): CombatPipelineState {
  return {
    pairCooldown: new Map(),
    impacts: [],
    knockoutDispatched: new Set(),
  };
}

export interface FighterHpMap {
  byCompositeId: Map<number, number>;
  getHp(compositeId: number): number;
  setHp(compositeId: number, hp: number): void;
}

export function buildFighterHpMap(
  fighters: CoreFighterRuntime[],
): FighterHpMap {
  const byCompositeId = new Map<number, number>();
  for (const f of fighters) {
    byCompositeId.set(f.composite.id, f.hp);
  }
  return {
    byCompositeId,
    getHp(id) {
      return byCompositeId.get(id) ?? 0;
    },
    setHp(id, hp) {
      byCompositeId.set(id, Math.max(0, hp));
      const fighter = fighters.find((f) => f.composite.id === id);
      if (fighter) fighter.hp = byCompositeId.get(id)!;
    },
  };
}

export function applyDamageToComposite(
  compositeId: number,
  amount: number,
  fighter: CoreFighterRuntime | undefined,
  hpMap: FighterHpMap,
  damageTypeId = "blunt",
  globalDamageMult = 1,
): number {
  if (amount <= 0) return 0;
  let dmg = amount * globalDamageMult;
  const dtype = getDamageType(damageTypeId);
  if (fighter?.isBotDamageTarget) {
    dmg *= BOT_DAMAGE_MULTIPLIER;
  }
  if (fighter?.defensePct) {
    const effectiveDef = fighter.defensePct * (1 - (dtype.pierceIgnoreDefPct ?? 0));
    dmg *= 1 - effectiveDef / 100;
  }
  const next = Math.max(0, hpMap.getHp(compositeId) - dmg);
  hpMap.setHp(compositeId, next);
  return dmg;
}

export function handleFighterCollision(
  bodyA: Body,
  bodyB: Body,
  compositeA: number,
  compositeB: number,
  contact: { x: number; y: number } | undefined,
  opts: {
    now: number;
    battleStartMs: number;
    spawnGraceMs?: number;
    battleOver: boolean;
    fighters: CoreFighterRuntime[];
    allComposites: Composite[];
    hpMap: FighterHpMap;
    playerCompositeId?: number;
    opponentCompositeId?: number;
    grabCtx: GrabDamageContext;
    grab?: GrabController;
    fxConfig: CombatFxConfig;
    pipeline: CombatPipelineState;
    events: BattleEventBus;
    rng: () => number;
    onDisarm?: (fighterCompositeId: number, itemComposite: Composite) => void;
    /** Sudden death: глобальный множитель урона (1 до лимита времени). */
    globalDamageMult?: number;
  },
): void {
  const {
    now,
    battleStartMs,
    spawnGraceMs,
    battleOver,
    fighters,
    allComposites,
    hpMap,
    playerCompositeId,
    opponentCompositeId,
    grabCtx,
    grab,
    fxConfig,
    pipeline,
    events,
    rng,
    onDisarm,
  } = opts;

  if (battleOver) return;
  if (isBattleSpawnGrace(battleStartMs, now, spawnGraceMs)) return;
  if (grab?.isAttachDamageGrace(now)) return;
  if ([bodyA, bodyB].every(isSaveBody)) return;

  const tradeOpts = {
    battleOver,
    playerHp: playerCompositeId ? hpMap.getHp(playerCompositeId) : 0,
    opponentHp: opponentCompositeId ? hpMap.getHp(opponentCompositeId) : 0,
    playerCompositeId,
    opponentCompositeId,
  };

  if (!canFightersTradeDamage(compositeA, compositeB, allComposites, tradeOpts)) {
    return;
  }

  const fighterKey = `${Math.min(compositeA, compositeB)}-${Math.max(compositeA, compositeB)}`;
  if ((pipeline.pairCooldown.get(fighterKey) ?? 0) > now) return;

  const rawHit = computeDamage(bodyA, bodyB);
  const filteredGrab = filterGrabDamage(compositeA, compositeB, rawHit, grabCtx);
  const fighterA = fighters.find((f) => f.composite.id === compositeA);
  const fighterB = fighters.find((f) => f.composite.id === compositeB);
  /** Владелец оружия (если тело — предмет в руках) или боец composite. */
  const fighterOfBody = (
    body: Body,
    byComposite: typeof fighterA,
  ): typeof fighterA => {
    const ownerId = (body.plugin as { ownerFighterId?: string } | undefined)
      ?.ownerFighterId;
    if (ownerId) {
      const owned = fighters.find((f) => f.id === ownerId);
      if (owned) return owned;
    }
    return byComposite;
  };
  const atkFromA = fighterOfBody(bodyA, fighterA);
  const atkFromB = fighterOfBody(bodyB, fighterB);
  const filteredFriendly = filterFriendlyWeaponDamage(
    bodyA,
    bodyB,
    atkFromA?.id ?? fighterA?.id,
    atkFromB?.id ?? fighterB?.id,
    filteredGrab.damageA,
    filteredGrab.damageB,
  );

  // Пассивы лодаута: atk / crit исходящего урона; headDef входящего в голову.
  const scaleOutgoing = (
    dmg: number,
    aggressor: typeof fighterA,
    victimBody: Body,
    victim: typeof fighterA,
  ) => {
    if (dmg <= 0 || !aggressor) return dmg;
    let next = dmg * (aggressor.loadoutMods?.atkMult ?? 1);
    const crit = aggressor.loadoutMods?.critChance ?? 0;
    if (crit > 0 && rng() < crit) next *= 2;
    if (
      victimBody.label === "Head" &&
      victim?.loadoutMods?.headDefBonus
    ) {
      next *= 1 - Math.min(0.6, victim.loadoutMods.headDefBonus);
    }
    return next;
  };
  const scaledFriendly = {
    damageA: scaleOutgoing(
      filteredFriendly.damageA,
      atkFromB,
      bodyA,
      fighterA,
    ),
    damageB: scaleOutgoing(
      filteredFriendly.damageB,
      atkFromA,
      bodyB,
      fighterB,
    ),
  };

  const result = filterDamageFromDeadAggressors(
    compositeA,
    compositeB,
    scaledFriendly.damageA,
    scaledFriendly.damageB,
    tradeOpts,
  );
  if (result.damageA <= 0 && result.damageB <= 0) return;

  pipeline.pairCooldown.set(fighterKey, now + FIGHTER_HIT_COOLDOWN_MS);

  const dmgA = applyDamageToComposite(
    compositeA,
    result.damageA,
    fighterA,
    hpMap,
    filteredGrab.damageTypeId,
    opts.globalDamageMult ?? 1,
  );
  const dmgB = applyDamageToComposite(
    compositeB,
    result.damageB,
    fighterB,
    hpMap,
    filteredGrab.damageTypeId,
    opts.globalDamageMult ?? 1,
  );

  const tryDisarm = (compositeId: number, damage: number) => {
    if (damage <= 0 || !onDisarm) return;
    const fighter = fighters.find((f) => f.composite.id === compositeId);
    if (!fighter) return;

    // Предмет в руках помечен ownerFighterId (tagItemOwner при захвате).
    const ownedBy = (b: { plugin?: unknown }) =>
      (b.plugin as { ownerFighterId?: string } | undefined)?.ownerFighterId ===
      fighter.id;
    const held = allComposites.find(
      (c) =>
        c.bodies.some(ownedBy) ||
        c.bodies.some(
          (b) =>
            b.parts &&
            b.parts.length > 1 &&
            b.parts.some((p) => p !== b && ownedBy(p)),
        ),
    );
    if (!held) return;

    const itemBody = held.bodies.find(
      (b) => (b.plugin as { itemId?: string } | undefined)?.itemId,
    );
    const itemId =
      itemBody && (itemBody.plugin as { itemId?: string }).itemId;
    if (!itemId) return;

    const def = items.all().find((d) => d.id === itemId);
    if (!def) return;

    const chance = computeDisarmChance(def, 0);
    if (rollDisarm(chance, rng)) {
      onDisarm(compositeId, held);
      events.emit("disarm", {
        fighterCompositeId: compositeId,
        itemCompositeId: held.id,
      });
    }
  };

  tryDisarm(compositeA, dmgA);
  tryDisarm(compositeB, dmgB);

  // Для FX: composite оружия → composite владельца (цвета / сторона).
  const fxComposite = (body: Body, compositeId: number): number =>
    fighterOfBody(body, undefined)?.composite.id ?? compositeId;
  const parties = resolveHitParties(
    { ...rawHit, damageA: dmgA, damageB: dmgB },
    fxComposite(bodyA, compositeA),
    fxComposite(bodyB, compositeB),
    fxConfig,
  );

  const cx = contact?.x ?? (bodyA.position.x + bodyB.position.x) / 2;
  const cy = contact?.y ?? (bodyA.position.y + bodyB.position.y) / 2;

  for (const party of parties) {
    if (party.victimDamage <= 0.5) continue;
    events.emit("hit", {
      victimCompositeId: party.victimCompositeId,
      aggressorCompositeId: party.aggressorCompositeId,
      damage: party.victimDamage,
      x: cx,
      y: cy,
      damageTypeId: filteredGrab.damageTypeId,
    });

    // Жертва захвата бьёт держателя → накопление forced release.
    if (grab) {
      for (const holder of fighters) {
        if (holder.composite.id !== party.victimCompositeId) continue;
        const holderGrab = grab.getPlayerGrab(holder.id);
        if (!isGrabbingFighter(holderGrab, party.aggressorCompositeId)) continue;
        grab.notifyVictimHit(holder.id, party.aggressorCompositeId, now);
      }
    }

    const hpAfter = hpMap.getHp(party.victimCompositeId);
    // victimDamage уже итоговый (множитель бота и защита применены в
    // applyDamageToComposite) — повторно не умножаем.
    if (
      !pipeline.knockoutDispatched.has(party.victimCompositeId) &&
      isKnockoutFromLethalHit(hpAfter, party.victimDamage)
    ) {
      pipeline.knockoutDispatched.add(party.victimCompositeId);
      events.emit("knockout", {
        victimCompositeId: party.victimCompositeId,
        winnerCompositeId: party.aggressorCompositeId,
      });
    }
  }

  const knockback = computeKnockback(rawHit, bodyA, bodyB);
  const pushScale = Math.min(1.35, 0.55 + rawHit.impactSpeed / 10);
  const victimIds = new Set(parties.map((p) => p.victimCompositeId));
  const bracedVictims = new Set(
    fighters
      .filter((f) => f.braceActive && victimIds.has(f.composite.id))
      .map((f) => f.composite.id),
  );

  const pushImpact = (body: Body, compositeId: number, impulse: Vector) => {
    const mag = Vector.magnitude(impulse);
    if (mag < 1e-6) return;
    let strength = pushScale;
    if (bracedVictims.has(compositeId)) {
      strength *= BRACE_KNOCKBACK_MULT;
    }
    pipeline.impacts.push({
      body,
      strength,
      vec: Vector.div(impulse, mag),
    });
  };

  const kbOutA = fighterA?.loadoutMods?.knockbackOutMult ?? 1;
  const kbOutB = fighterB?.loadoutMods?.knockbackOutMult ?? 1;
  pushImpact(
    bodyA,
    compositeA,
    Vector.mult(knockback.impulseA, kbOutB),
  );
  pushImpact(
    bodyB,
    compositeB,
    Vector.mult(knockback.impulseB, kbOutA),
  );
}

export function tickKnockbackImpacts(
  pipeline: CombatPipelineState,
  event: Matter.IEventTimestamped<Matter.Engine>,
  battleOver: boolean,
): void {
  if (battleOver) {
    pipeline.impacts = [];
    return;
  }

  const timeScale = event.delta ?? 16.667;
  const timeStep = timeScale / 1_000;
  const next: ImpactEntry[] = [];

  while (pipeline.impacts.length > 0) {
    const impact = pipeline.impacts.pop();
    if (!impact) break;
    const { body, strength, vec } = impact;
    if (isSaveBody(body)) continue;

    moveBody(body)(event, vec, KNOCKBACK_SPEED * strength);
    clampBodySpeed(body);

    if (strength > timeStep) {
      next.push({ body, strength: strength - timeStep, vec });
    }
  }

  pipeline.impacts = next;
}
