import Matter, {
  Body,
  Composite,
  Engine,
  Events,
  type Bounds,
} from "matter-js";
import {
  computeBotMoveIntent,
  createBotBrainState,
  tickBotAbilities,
} from "@/battle/aiLogic";
import { createArenaWalls } from "@/battle/headlessWalls";
import {
  BATTLE_GRAVITY,
  BATTLE_HARD_TIMEOUT_MS,
  BATTLE_OPENING_BRAWL_MS,
  BATTLE_SPAWN_GRACE_MS,
  WEAPON_HOLD_ENABLED,
  suddenDeathMultiplier,
} from "@/lib/battleTuning";
import { clampCompositeSpeed } from "@/lib/bodySpeed";
import { colorsForSide } from "@/lib/fighterColors";
import type { CombatFxConfig } from "@/lib/combatFx";
import { tagStickmanHands } from "@/lib/grab/hands";
import { moveBody, toMoveInput } from "@/lib/moveBody";
import { capturePoseSnapshot } from "@/lib/ragdollPoseReset";
import { updateMonsterRopeConstraints } from "@/monster/linkTypes";
import {
  dampStickmanLateralDrift,
  pullStickmanComToX,
  stickmanCom,
} from "@/lib/stickmanIdleDamp";
import { computeLoadoutCombatMods } from "@/loadout/applyPassives";
import {
  heldWeaponMoveMult,
  isHeldWeaponVsOwner,
} from "@/items/weaponHold";
import { encodeSnapshot } from "@/net/snapshot";
import type { NetInputPayload } from "@/net/protocol";
import {
  createAbilityState,
  tickFighterAbilities,
  emptyInput,
  type AbilityRuntimeState,
} from "./abilityTick";
import type { BattleClock } from "./clock";
import { createBattleClock } from "./clock";
import {
  buildFighterHpMap,
  createCombatPipelineState,
  handleFighterCollision,
  tickKnockbackImpacts,
  type CombatPipelineState,
} from "./combatPipeline";
import { BattleEventBus } from "./events";
import { GrabController } from "./grabController";
import type {
  BattleSessionConfig,
  BattleSnapshot,
  CoreFighterRuntime,
  CoreFighterSpec,
  FighterRole,
} from "./types";

const STEP_MS = 1000 / 60;

function registerBodies(composite: Composite, map: Map<number, number>): void {
  for (const body of composite.bodies) {
    map.set(body.id, composite.id);
    // Compound parts приходят в collision events — без них нет урона от оружия.
    if (body.parts && body.parts.length > 1) {
      for (const part of body.parts) {
        if (part !== body) map.set(part.id, composite.id);
      }
    }
  }
}

function initFighter(spec: CoreFighterSpec): CoreFighterRuntime {
  for (const body of spec.composite.bodies) {
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }
  // Weapon hold / grab нуждаются в plugin.part на руках.
  tagStickmanHands(spec.composite, spec.id);
  const loadoutMods = spec.loadout
    ? computeLoadoutCombatMods(spec.loadout, spec.extraItems)
    : {
        atkMult: 1,
        defPct: 0,
        moveMult: 1,
        knockbackOutMult: 1,
        critChance: 0,
        headDefBonus: 0,
      };
  // Если defensePct не задан явно — подтягиваем из пассивов лодаута.
  let defensePct = spec.defensePct;
  if (defensePct == null && loadoutMods.defPct > 0) {
    defensePct = loadoutMods.defPct;
  }
  return {
    ...spec,
    defensePct,
    loadoutMods,
    hp: spec.maxHp,
    brain: spec.aiProfile ? createBotBrainState() : undefined,
    input: emptyInput(),
    moveSpeedMult: loadoutMods.moveMult,
    inputBlocked: false,
    braceActive: false,
  };
}

export class BattleSession {
  readonly engine: Engine;
  readonly walls: Composite;
  readonly fighters: CoreFighterRuntime[];
  readonly itemComposites: Composite[];
  readonly allComposites: Composite[];
  readonly bounds: Bounds;
  readonly events = new BattleEventBus();
  readonly grab = new GrabController();

  private readonly bodyComposite = new Map<number, number>();
  private readonly pipeline: CombatPipelineState = createCombatPipelineState();
  private readonly abilities = new Map<FighterRole, AbilityRuntimeState>();
  private readonly hpMap;
  private readonly fxConfig: CombatFxConfig;
  private readonly playerCompositeId?: number;
  private readonly opponentCompositeId?: number;
  private battleStartMs: number;
  private damageLocked: boolean;
  private spawnGraceMs: number;
  private tickCount = 0;
  private battleEndEmitted = false;
  private timedOut = false;
  private clock: BattleClock;
  private onDisarm?: (fighterCompositeId: number, item: Composite) => void;
  /** Якорь COM.x для idle-симметрии (обновляется при движении). */
  private readonly idleAnchorX = new Map<FighterRole, number>();
  /** true только если session сам создал Engine — иначе нельзя Engine.clear. */
  private readonly ownsEngine: boolean;
  private readonly collisionHandler: (
    event: Matter.IEventCollision<Engine>,
  ) => void;
  /** Отключает физику held weapon ↔ владелец (pin иначе взрывается). */
  private readonly heldWeaponPairFilter: (
    event: Matter.IEventCollision<Engine>,
  ) => void;

  constructor(
    config: BattleSessionConfig,
    clock: BattleClock = createBattleClock(config.battleStartMs ?? 1000),
  ) {
    this.clock = clock;
    this.battleStartMs = config.battleStartMs ?? 1000;
    this.damageLocked = config.damageLocked ?? false;
    this.spawnGraceMs = config.spawnGraceMs ?? BATTLE_SPAWN_GRACE_MS;
    this.bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: config.arenaSize, y: config.arenaSize },
    ]);

    this.ownsEngine = !config.engine;
    this.engine = config.engine ?? Engine.create({ gravity: BATTLE_GRAVITY });
    this.grab.setEngine(this.engine);
    this.walls = config.walls ?? createArenaWalls(this.bounds, config.arenaSize);
    this.fighters = config.fighters.map(initFighter);
    this.itemComposites = config.itemComposites ?? [];
    this.grab.setItemComposites(this.itemComposites);
    this.allComposites = [
      ...this.fighters.map((f) => f.composite),
      ...this.itemComposites,
    ];

    this.playerCompositeId = config.playerCompositeId;
    this.opponentCompositeId = config.opponentCompositeId;

    this.fxConfig = {
      playerCompositeId: config.playerCompositeId,
      opponentCompositeId: config.opponentCompositeId,
      playerColors: colorsForSide("player"),
      opponentColors: colorsForSide("opponent"),
    };

    if (!config.compositesInWorld) {
      Composite.add(this.engine.world, [
        this.walls,
        ...this.fighters.map((f) => f.composite),
        ...this.itemComposites,
      ]);
    }

    // Стены НЕ регистрируем в bodyComposite: иначе боец, лежащий у стены/пола,
    // постоянно «получает удары» от статичных тел и теряет HP сам по себе.
    for (const f of this.fighters) {
      registerBodies(f.composite, this.bodyComposite);
      this.abilities.set(f.id, createAbilityState(capturePoseSnapshot(f.composite)));
    }
    for (const item of this.itemComposites) {
      registerBodies(item, this.bodyComposite);
    }

    this.hpMap = buildFighterHpMap(this.fighters);

    const grabStateFor = (compositeId: number | undefined) => {
      if (!compositeId) return null;
      const fighter = this.fighters.find((f) => f.composite.id === compositeId);
      return fighter ? this.grab.getPlayerGrab(fighter.id) : null;
    };

    this.heldWeaponPairFilter = (event) => {
      for (const pair of event.pairs) {
        if (isHeldWeaponVsOwner(pair.bodyA, pair.bodyB)) {
          pair.isActive = false;
        }
      }
    };

    this.collisionHandler = (event) => {
      const now = this.clock.now();
      this.heldWeaponPairFilter(event);
      this.grab.handleCollision(
        event,
        this.fighters,
        [...this.allComposites, this.walls],
        this.itemComposites,
        now,
      );

      for (const pair of event.pairs) {
        const { bodyA, bodyB, collision } = pair;
        if (bodyA.isStatic && bodyB.isStatic) continue;
        if (this.damageLocked) continue;
        if (isHeldWeaponVsOwner(bodyA, bodyB)) continue;
        const compositeA = this.bodyComposite.get(bodyA.id);
        const compositeB = this.bodyComposite.get(bodyB.id);
        if (!(compositeA && compositeB) || compositeA === compositeB) continue;

        handleFighterCollision(
          bodyA,
          bodyB,
          compositeA,
          compositeB,
          collision.supports[0],
          {
            now,
            battleStartMs: this.battleStartMs,
            spawnGraceMs: this.spawnGraceMs,
            battleOver: this.isBattleOver(),
            fighters: this.fighters,
            allComposites: this.allComposites,
            hpMap: this.hpMap,
            playerCompositeId: this.playerCompositeId,
            opponentCompositeId: this.opponentCompositeId,
            grabCtx: {
              playerCompositeId: this.playerCompositeId,
              opponentCompositeId: this.opponentCompositeId,
              playerGrab: grabStateFor(this.playerCompositeId),
              opponentGrab: grabStateFor(this.opponentCompositeId),
            },
            grab: this.grab,
            globalDamageMult: suddenDeathMultiplier(this.getElapsedMs()),
            fxConfig: this.fxConfig,
            pipeline: this.pipeline,
            events: this.events,
            rng: () => this.clock.random(),
            onDisarm: this.onDisarm,
          },
        );
      }
    };
    Events.on(this.engine, "collisionStart", this.collisionHandler);
    Events.on(this.engine, "collisionActive", this.heldWeaponPairFilter);
  }

  setDisarmHandler(
    handler: (fighterCompositeId: number, item: Composite) => void,
  ): void {
    this.onDisarm = handler;
  }

  setInput(fighterId: FighterRole, input: NetInputPayload): void {
    const fighter = this.fighters.find((f) => f.id === fighterId);
    if (!fighter || this.isBattleOver()) return;
    fighter.input = input;
  }

  setClock(clock: BattleClock): void {
    this.clock = clock;
  }

  getFighter(id: FighterRole): CoreFighterRuntime | undefined {
    return this.fighters.find((f) => f.id === id);
  }

  getAbilityState(id: FighterRole): AbilityRuntimeState | undefined {
    return this.abilities.get(id);
  }

  /** Снять spawn-lock и начать окно spawn grace (после серверного settle). */
  beginBattle(): void {
    this.damageLocked = false;
    this.timedOut = false;
    this.battleStartMs = this.clock.now();
    for (const fighter of this.fighters) {
      this.idleAnchorX.set(fighter.id, stickmanCom(fighter.composite).x);
      if (!fighter.brain) continue;
      fighter.brain.battleStartMs = this.battleStartMs;
      fighter.brain.grabCooldownUntil =
        this.battleStartMs + BATTLE_OPENING_BRAWL_MS;
    }
  }

  isDamageLocked(): boolean {
    return this.damageLocked;
  }

  getHp(fighterId: FighterRole): number {
    const f = this.getFighter(fighterId);
    return f?.hp ?? 0;
  }

  /** Игровое время боя (по sim-часам, не wall clock). */
  getElapsedMs(): number {
    return Math.max(0, this.clock.now() - this.battleStartMs);
  }

  isBattleOver(): boolean {
    if (this.timedOut) return true;
    const alive = this.fighters.filter((f) => f.hp > 0);
    if (alive.length === 0) return true;
    // Командный режим: осталась одна команда среди живых.
    if (this.hasTeams()) {
      const teams = new Set(alive.map((f) => f.team));
      return teams.size <= 1;
    }
    if (alive.length <= 1 && this.fighters.length > 1) return true;
    return false;
  }

  /** Победитель — id бойца (FFA) или любого живого из победившей команды. */
  resolveWinner(): FighterRole | null {
    const alive = this.fighters.filter((f) => f.hp > 0);
    if (alive.length === 0) return null;
    if (this.hasTeams()) {
      const teams = new Set(alive.map((f) => f.team));
      if (teams.size === 1) return alive[0]!.id;
    } else if (alive.length === 1) {
      return alive[0]!.id;
    }
    // Тайм-аут (или снапшот незаконченного боя): побеждает больший HP,
    // равенство лидеров — ничья.
    let best = alive[0]!;
    for (const f of alive) {
      if (f.hp > best.hp) best = f;
    }
    const leaders = alive.filter((f) => f.hp === best.hp);
    if (leaders.length > 1) return null;
    return best.id;
  }

  private hasTeams(): boolean {
    return this.fighters.some((f) => f.team !== undefined);
  }

  /** Ближайший живой враг (другая команда или любой другой в FFA). */
  private findEnemy(fighter: CoreFighterRuntime): CoreFighterRuntime | undefined {
    let best: CoreFighterRuntime | undefined;
    let bestDist = Infinity;
    for (const other of this.fighters) {
      if (other.id === fighter.id || other.hp <= 0) continue;
      if (
        fighter.team !== undefined &&
        other.team !== undefined &&
        other.team === fighter.team
      ) {
        continue;
      }
      const dx = other.head.position.x - fighter.head.position.x;
      const dy = other.head.position.y - fighter.head.position.y;
      const d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = other;
      }
    }
    return best;
  }

  tick(dtMs = STEP_MS, advanceEngine = true): void {
    if (this.isBattleOver()) {
      this.emitBattleEndOnce();
      return;
    }

    const clock = this.clock as BattleClock & { advance?: (ms: number) => void };
    clock.advance?.(dtMs);
    const now = this.clock.now();

    // Жёсткий тайм-аут: победа по HP (равенство — ничья через resolveWinner).
    if (!this.damageLocked && this.getElapsedMs() >= BATTLE_HARD_TIMEOUT_MS) {
      this.timedOut = true;
      this.emitBattleEndOnce();
      return;
    }

    const fakeEvent = { delta: dtMs } as unknown as Matter.IEventTimestamped<Engine>;

    for (const fighter of this.fighters) {
      if (fighter.hp <= 0) continue;

      this.grab.syncInput(fighter, now);
      if (WEAPON_HOLD_ENABLED && this.itemComposites.length) {
        this.grab.tryAutoPickup(fighter, this.itemComposites, now);
      }

      // Тяжёлое оружие в руках режет скорость (abilityTick тоже пишет moveSpeedMult).
      const grabState = this.grab.getPlayerGrab(fighter.id);
      const weaponSlow =
        WEAPON_HOLD_ENABLED && grabState
          ? heldWeaponMoveMult(grabState, this.itemComposites)
          : 1;

      const ability = this.abilities.get(fighter.id)!;

      if (fighter.aiProfile && fighter.brain) {
        const enemy = this.findEnemy(fighter);
        if (enemy) {
          const intent = computeBotMoveIntent(
            fighter.aiProfile,
            fighter.brain,
            fighter.head,
            enemy.head,
            this.bounds,
            now,
          );
          tickBotAbilities(
            fighter.aiProfile,
            fighter.brain,
            fighter.composite,
            fighter.head,
            enemy.head,
            now,
          );
          fighter.input = {
            ...fighter.input,
            grabL: intent.grabL,
            grabR: intent.grabR,
          };
          fighter.moveSpeedMult =
            (fighter.loadoutMods?.moveMult ?? 1) * weaponSlow;
          moveBody(fighter.head)(
            fakeEvent,
            toMoveInput(intent.worldMove),
            intent.speed * weaponSlow,
          );
          clampCompositeSpeed(fighter.composite);
        }
      } else {
        tickFighterAbilities(fighter, ability, fakeEvent, now, () =>
          this.clock.random(),
        );
        fighter.moveSpeedMult *= weaponSlow;
        // Защита от разгона в стену — как у AI-бойцов.
        clampCompositeSpeed(fighter.composite);
      }

      // one-shot: grab (drop) + abilityTick (abilitySlot) уже прочитали
      if (fighter.input.dropWeapon || fighter.input.abilitySlot) {
        fighter.input = {
          ...fighter.input,
          dropWeapon: false,
          abilitySlot: false,
        };
      }

      const moving =
        Math.abs(fighter.input.move.x) > 0.01 ||
        Math.abs(fighter.input.move.y) > 0.01;
      if (moving) {
        this.idleAnchorX.set(fighter.id, stickmanCom(fighter.composite).x);
      } else if (!fighter.aiProfile) {
        // Idle: падает, но не уползает вбок (симметрия).
        dampStickmanLateralDrift(fighter.composite, 0.22);
        const anchor = this.idleAnchorX.get(fighter.id);
        if (anchor !== undefined) {
          pullStickmanComToX(fighter.composite, anchor, 0.0007);
        }
      }
    }

    tickKnockbackImpacts(this.pipeline, fakeEvent, this.isBattleOver());
    // Верёвки: slack→tight каждый кадр (иначе в headless/dedicated rope «плывёт»).
    for (const fighter of this.fighters) {
      updateMonsterRopeConstraints(fighter.composite);
    }
    for (const item of this.itemComposites) {
      updateMonsterRopeConstraints(item);
    }
    if (advanceEngine) {
      Engine.update(this.engine, dtMs);
    }
    this.tickCount++;

    if (this.isBattleOver()) {
      this.emitBattleEndOnce();
    }
  }

  private emitBattleEndOnce(): void {
    if (this.battleEndEmitted) return;
    this.battleEndEmitted = true;
    this.events.emit("battleEnd", { winner: this.resolveWinner() });
  }

  snapshot(): BattleSnapshot {
    const composites = [
      this.walls,
      ...this.fighters.map((f) => f.composite),
      ...this.itemComposites,
    ];
    const fighterHp: Record<FighterRole, number> = {};
    for (const f of this.fighters) {
      fighterHp[f.id] = f.hp;
    }
    return {
      tick: this.tickCount,
      t: this.clock.now(),
      bodies: encodeSnapshot(composites),
      fighterHp,
      battleOver: this.isBattleOver(),
      winner: this.resolveWinner(),
    };
  }

  destroy(): void {
    // Снимаем только СВОЙ обработчик: движок общий, Events.off без callback
    // снёс бы обработчики других систем (захваты, импакты) после рематча.
    Events.off(this.engine, "collisionStart", this.collisionHandler);
    Events.off(this.engine, "collisionActive", this.heldWeaponPairFilter);
    // Нельзя Engine.clear на shared matter4react engine — сотрёт стены/бойцов,
    // которые React Composite всё ещё считает живыми (rematch / unmount).
    if (this.ownsEngine) {
      Engine.clear(this.engine);
    }
    this.events.clear();
  }
}

export function createBattleSession(
  config: BattleSessionConfig,
  clock?: BattleClock,
): BattleSession {
  return new BattleSession(config, clock);
}
