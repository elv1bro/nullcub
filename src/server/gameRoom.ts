import Matter, { Body, Composite } from "matter-js";
import { createStickman } from "@/utils/createStickman";
import { tagStickmanHands } from "@/lib/grab/hands";
import { createArenaWalls } from "@/battle/headlessWalls";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { getAiProfile, type AiDifficultyId } from "@/battle/aiProfiles";
import { MAX_HP, OPPONENT_MAX_HP } from "@/lib/combat";
import { createBattleSession, type BattleSession } from "@/core/battleSession";
import { encodeBodiesOrdered } from "@/net/snapshot";
import type { WsLobbyPlayer } from "@/net/transport";
import { WS_MAX_SLOTS } from "@/net/transport";
import { clampMove, InputRateLimiter } from "./inputValidator";

import {
  SERVER_SETTLE_TICKS,
  SERVER_SPAWN_GRACE_MS,
} from "./serverConstants";

export {
  SERVER_BUILD_ID,
  SERVER_SETTLE_TICKS,
  SERVER_SPAWN_GRACE_MS,
} from "./serverConstants";
const TICK_MS = 1000 / 60;
const REMATCH_RESET_MS = 2500;
import type { GameRoomDebugInfo } from "./debugTypes";

export type { GameRoomDebugInfo } from "./debugTypes";

/** Классические роли + слоты 3–4. */
export type FighterRole = "player" | "opponent" | "p2" | "p3" | string;

const SLOT_ORDER: FighterRole[] = ["player", "opponent", "p2", "p3"];

export interface RoomClient {
  id: string;
  name: string;
  /** Основной fighterId (первый слот клиента). */
  fighterId: FighterRole;
  /** Все слоты, которыми владеет этот сокет (локальный 2P). */
  ownedFighterIds?: FighterRole[];
  send: (msg: unknown) => void;
  limiter: InputRateLimiter;
  ready?: boolean;
}

interface SlotState {
  fighterId: FighterRole;
  clientId: string;
  name: string;
  ready: boolean;
  team: number;
}

export interface GameRoomOptions {
  roomId: string;
  /** Секрет из duel code; join без совпадения отклоняется. */
  secret: string;
  arenaSize?: number;
  onEmpty?: () => void;
  debug?: boolean;
  /** Vitest: settle синхронно. Prod: async батчами без блокировки WS. */
  syncSettle?: boolean;
  /** Спавнить оружие на арене (выкл. для idle-stability без item-chip). */
  spawnItems?: boolean;
  maxSlots?: number;
}

export class GameRoom {
  readonly roomId: string;
  readonly secret: string;
  readonly clients = new Map<string, RoomClient>();
  private slots = new Map<FighterRole, SlotState>();
  private session: BattleSession | null = null;
  private tickTimer: ReturnType<typeof setInterval> | null = null;
  private snapshotTimer: ReturnType<typeof setInterval> | null = null;
  private battleStateTimer: ReturnType<typeof setInterval> | null = null;
  private readonly arenaSize: number;
  private readonly onEmpty?: () => void;
  private battleStarted = false;
  private lastBattleState = "";
  /** Тела в детерминированном порядке для ordered-snapshot. */
  private orderedBodies: Body[] = [];
  private readonly debug: boolean;
  private readonly syncSettle: boolean;
  private readonly spawnItems: boolean;
  private readonly maxSlots: number;
  private readonly events: string[] = [];
  private resetTimer: ReturnType<typeof setTimeout> | null = null;
  /** FFA (каждый сам) или пати из людей + AI-союзники vs 1 бот. */
  private battleMode: "ffa" | "partyBots" = "ffa";
  private botDifficulty: AiDifficultyId = "normal";

  constructor(opts: GameRoomOptions) {
    this.roomId = opts.roomId;
    this.secret = opts.secret;
    this.arenaSize = opts.arenaSize ?? 1000;
    this.debug = opts.debug ?? false;
    this.syncSettle = opts.syncSettle ?? process.env["VITEST"] === "true";
    this.spawnItems = opts.spawnItems ?? true;
    this.maxSlots = Math.min(WS_MAX_SLOTS, Math.max(2, opts.maxSlots ?? WS_MAX_SLOTS));
    if (opts.onEmpty) this.onEmpty = opts.onEmpty;
  }

  /** Constant-time-ish compare для коротких hex-секретов. */
  matchesSecret(candidate: string): boolean {
    if (typeof candidate !== "string" || candidate.length !== this.secret.length) {
      return false;
    }
    let diff = 0;
    for (let i = 0; i < this.secret.length; i++) {
      diff |= this.secret.charCodeAt(i) ^ candidate.charCodeAt(i);
    }
    return diff === 0;
  }

  private logEvent(message: string): void {
    if (!this.debug) return;
    const line = `${new Date().toISOString().slice(11, 23)} ${message}`;
    this.events.push(line);
    if (this.events.length > 80) this.events.shift();
  }

  getDebugInfo(): GameRoomDebugInfo {
    const session = this.session;
    return {
      roomId: this.roomId,
      battleStarted: this.battleStarted,
      players: this.lobbyPlayers(),
      playerHp: session ? session.getHp("player") : null,
      opponentHp: session ? session.getHp("opponent") : null,
      battleOver: session?.isBattleOver() ?? false,
      events: [...this.events],
    };
  }

  private nextFreeSlot(prefer?: FighterRole): FighterRole | null {
    if (prefer && !this.slots.has(prefer) && SLOT_ORDER.includes(prefer)) {
      const idx = SLOT_ORDER.indexOf(prefer);
      if (idx >= 0 && idx < this.maxSlots) return prefer;
    }
    for (let i = 0; i < this.maxSlots; i++) {
      const id = SLOT_ORDER[i]!;
      if (!this.slots.has(id)) return id;
    }
    return null;
  }

  addClient(client: RoomClient): FighterRole | null {
    if (this.clients.has(client.id)) return client.fighterId;
    if (this.battleStarted) return null;

    const name =
      typeof client.name === "string"
        ? client.name.replace(/[\u0000-\u001f]/g, "").slice(0, 32) || "Fighter"
        : "Fighter";
    client.name = name;

    const requested = client.fighterId;
    // Предпочитаем запрошенную роль, иначе — первый свободный слот.
    // Если preferred занят, отдаём следующий (лобби на 3–4), а не reject:
    // иначе нельзя набрать комнату без явных role=p2/p3.
    const prefer =
      requested === "player" || requested === "opponent" ? requested : undefined;
    const slot =
      prefer && !this.slots.has(prefer)
        ? prefer
        : this.nextFreeSlot(undefined);
    if (!slot) return null;

    client.fighterId = slot;
    client.ownedFighterIds = client.ownedFighterIds?.length
      ? client.ownedFighterIds
      : [slot];
    if (!client.ownedFighterIds.includes(slot)) {
      client.ownedFighterIds = [slot];
    }
    client.ready = false;
    this.clients.set(client.id, client);
    this.slots.set(slot, {
      fighterId: slot,
      clientId: client.id,
      name,
      ready: false,
      team: this.battleMode === "partyBots" ? 0 : SLOT_ORDER.indexOf(slot),
    });
    // Legacy aliases для debug / старых тестов.
    this.clients.set(`${slot}-slot`, client);

    this.logEvent(`join ${client.name} (${slot})`);
    this.broadcastLobby();
    return slot;
  }

  /** Локальный второй игрок на том же сокете. */
  claimLocal(clientId: string, name: string): FighterRole | null {
    const client = this.clients.get(clientId);
    if (!client || this.battleStarted) return null;
    client.ownedFighterIds ??= [client.fighterId];
    if (client.ownedFighterIds.length >= 2) return null;
    const slot = this.nextFreeSlot();
    if (!slot) return null;
    const clean =
      typeof name === "string"
        ? name.replace(/[\u0000-\u001f]/g, "").slice(0, 32) || "P2"
        : "P2";
    client.ownedFighterIds.push(slot);
    this.slots.set(slot, {
      fighterId: slot,
      clientId,
      name: clean,
      ready: client.ready ?? false,
      team: this.battleMode === "partyBots" ? 0 : SLOT_ORDER.indexOf(slot),
    });
    this.clients.set(`${slot}-slot`, client);
    this.logEvent(`claimLocal ${clean} (${slot}) by ${client.name}`);
    this.broadcastLobby();
    return slot;
  }

  releaseLocal(clientId: string, fighterId: string): void {
    const client = this.clients.get(clientId);
    if (!client || this.battleStarted) return;
    if (fighterId === client.fighterId) return;
    client.ownedFighterIds ??= [client.fighterId];
    if (!client.ownedFighterIds.includes(fighterId)) return;
    client.ownedFighterIds = client.ownedFighterIds.filter((id) => id !== fighterId);
    this.slots.delete(fighterId);
    this.clients.delete(`${fighterId}-slot`);
    this.broadcastLobby();
  }

  setBattleMode(
    mode: "ffa" | "partyBots",
    difficulty?: AiDifficultyId,
  ): void {
    if (this.battleStarted) return;
    this.battleMode = mode;
    if (difficulty) this.botDifficulty = difficulty;
    if (mode === "partyBots") {
      for (const slot of this.slots.values()) slot.team = 0;
    } else {
      for (const [id, slot] of this.slots) {
        slot.team = SLOT_ORDER.indexOf(id);
      }
    }
    this.logEvent(`battleMode → ${mode} (${this.botDifficulty})`);
    this.broadcastLobby();
  }

  setReady(clientId: string, ready: boolean): void {
    const client = this.clients.get(clientId);
    if (!client) return;
    client.ready = ready;
    for (const id of client.ownedFighterIds ?? [client.fighterId]) {
      const slot = this.slots.get(id);
      if (slot) slot.ready = ready;
    }
    this.logEvent(`ready ${client.name} → ${ready ? "yes" : "no"}`);
    this.broadcastLobby();
    this.tryStartBattle();
  }

  removeClient(clientId: string): void {
    const client = this.clients.get(clientId);
    if (!client) return;

    const leftIds = [...(client.ownedFighterIds ?? [client.fighterId])];
    this.clients.delete(clientId);
    for (const id of leftIds) {
      this.slots.delete(id);
      this.clients.delete(`${id}-slot`);
    }
    this.logEvent(`leave ${client.name} (${leftIds.join(",")})`);

    if (this.battleStarted && this.session && !this.session.isBattleOver()) {
      for (const leftRole of leftIds) {
        this.broadcast({ type: "opponent_left", role: leftRole });
        const left = this.session.getFighter(leftRole);
        if (left) left.hp = 0;
      }
      this.broadcastBattleState(true);
      if (this.session.isBattleOver()) this.scheduleRematchReset();
      this.logEvent(`forfeit → remaining win`);
    }

    if (this.clients.size === 0 || [...this.clients.keys()].every((k) => k.endsWith("-slot"))) {
      // Только alias-ключи остались
      const real = [...this.clients.keys()].filter((k) => !k.endsWith("-slot"));
      if (real.length === 0) {
        this.destroy();
        this.onEmpty?.();
        return;
      }
    }
    this.broadcastLobby();
  }

  private lobbyPlayers(): WsLobbyPlayer[] {
    const players: WsLobbyPlayer[] = [];
    for (const id of SLOT_ORDER) {
      const slot = this.slots.get(id);
      if (!slot) continue;
      players.push({
        fighterId: slot.fighterId,
        name: slot.name,
        ready: slot.ready,
        team: slot.team,
        ownerClientId: slot.clientId,
      });
    }
    return players;
  }

  private broadcastLobby(): void {
    if (this.battleStarted) return;
    this.broadcast({ type: "lobby", players: this.lobbyPlayers() });
  }

  handleInput(clientId: string, raw: unknown, fighterId?: string): void {
    const client = this.clients.get(clientId);
    const session = this.session;
    if (!client || !session || session.isBattleOver()) return;
    if (!this.battleStarted || session.isDamageLocked()) return;
    const now = performance.now();
    if (!client.limiter.accept(now)) return;
    let input;
    try {
      input = clampMove(raw);
    } catch {
      return;
    }
    const owned = client.ownedFighterIds ?? [client.fighterId];
    const target =
      fighterId && owned.includes(fighterId) ? fighterId : client.fighterId;
    const fighter = session.getFighter(target);
    if (!fighter || fighter.hp <= 0) return;
    session.setInput(target, input);
  }

  /** Headless tick для тестов (без setInterval). */
  tickBattle(dtMs = TICK_MS): void {
    this.session?.tick(dtMs);
  }

  private tryStartBattle(): void {
    if (this.battleStarted) return;
    const filled = this.lobbyPlayers();
    if (this.battleMode === "partyBots") {
      // Пати vs бот: хватает 1 готового человека; пустые = AI-союзники.
      if (filled.length < 1) return;
      if (!filled.every((p) => p.ready)) return;
      this.startBattleFromRoster(this.buildPartyBotsRoster(filled));
      return;
    }
    // Минимум 2 слота (классический дуэль) и все готовы.
    if (filled.length < 2) return;
    if (!filled.every((p) => p.ready)) return;

    const n = filled.length;
    const stickmen = filled.map((p, i) => {
      const x = ((i + 1) / (n + 1)) * this.arenaSize;
      return this.makeStickmanSlot({
        fighterId: p.fighterId,
        name: p.name,
        team: p.team ?? i,
        x,
        y: this.arenaSize / 2,
      });
    });
    this.startBattleFromRoster(
      stickmen.map((s, i) => ({
        ...s,
        maxHp: i === 0 ? MAX_HP : OPPONENT_MAX_HP,
        aiProfile: null as ReturnType<typeof getAiProfile> | null,
      })),
    );
  }

  private buildPartyBotsRoster(filled: WsLobbyPlayer[]) {
    const ai = getAiProfile(this.botDifficulty);
    const party: Array<{
      fighterId: string;
      name: string;
      team: number;
      x: number;
      y: number;
      maxHp: number;
      aiProfile: ReturnType<typeof getAiProfile> | null;
    }> = [];

    for (let i = 0; i < filled.length; i++) {
      const p = filled[i]!;
      party.push({
        fighterId: p.fighterId,
        name: p.name,
        team: 0,
        x: this.arenaSize * 0.28,
        y: this.arenaSize * (0.32 + i * 0.12),
        maxHp: MAX_HP,
        aiProfile: null,
      });
    }
    let ally = 1;
    while (party.length < 4) {
      const i = party.length;
      party.push({
        fighterId: `ally${ally}`,
        name: `Ally ${ally}`,
        team: 0,
        x: this.arenaSize * 0.28,
        y: this.arenaSize * (0.32 + i * 0.12),
        maxHp: MAX_HP,
        aiProfile: ai,
      });
      ally += 1;
    }
    party.push({
      fighterId: "bossBot",
      name: "Boss Bot",
      team: 1,
      x: this.arenaSize * 0.72,
      y: this.arenaSize * 0.5,
      maxHp: Math.round(MAX_HP * 2.2),
      aiProfile: ai,
    });
    return party.map((p) => ({
      ...this.makeStickmanSlot(p),
      maxHp: p.maxHp,
      aiProfile: p.aiProfile,
    }));
  }

  private makeStickmanSlot(opts: {
    fighterId: string;
    name: string;
    team: number;
    x: number;
    y: number;
  }) {
    const sm = createStickman(opts.x, opts.y, {
      render: { visible: false },
    });
    tagStickmanHands(sm, opts.fighterId);
    for (const body of sm.bodies) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }
    return {
      fighterId: opts.fighterId,
      name: opts.name,
      team: opts.team,
      composite: sm,
    };
  }

  private startBattleFromRoster(
    roster: Array<{
      fighterId: string;
      name: string;
      team: number;
      composite: Matter.Composite;
      maxHp: number;
      aiProfile: ReturnType<typeof getAiProfile> | null;
    }>,
  ): void {
    if (this.battleStarted) return;
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: this.arenaSize, y: this.arenaSize },
    ]);
    const walls = createArenaWalls(bounds, this.arenaSize);
    const stickmen = roster;
    const n = stickmen.length;

    const items = this.spawnItems
      ? spawnArenaItems(DEFAULT_ARENA_ITEMS, [...ARENA_ITEM_SPAWN_POSITIONS])
      : [];

    const fighters = stickmen.map((s) => {
      const head = s.composite.bodies.find((b) => b.label === "Head")!;
      return {
        id: s.fighterId,
        composite: s.composite,
        head,
        maxHp: s.maxHp,
        team: s.team,
        aiProfile: s.aiProfile,
        isBotDamageTarget: s.team === 0 && !s.aiProfile,
      };
    });

    this.session = createBattleSession({
      arenaSize: this.arenaSize,
      walls,
      compositesInWorld: true,
      damageLocked: true,
      spawnGraceMs: SERVER_SPAWN_GRACE_MS,
      fighters,
      itemComposites: items,
      playerCompositeId: stickmen[0]?.composite.id,
      opponentCompositeId: stickmen.find((s) => s.team === 1)?.composite.id
        ?? stickmen[1]?.composite.id,
      battleStartMs: performance.now(),
    });

    Composite.add(this.session.engine.world, [
      walls,
      ...stickmen.map((s) => s.composite),
      ...items,
    ]);

    this.session.events.on("hit", (hit) => {
      const victim =
        stickmen.find((s) => s.composite.id === hit.victimCompositeId)?.fighterId ??
        "opponent";
      this.broadcast({
        type: "hit",
        payload: {
          victimId: victim,
          damage: hit.damage,
          damageType: hit.damageTypeId ?? "blunt",
          x: hit.x,
          y: hit.y,
        },
      });
    });

    this.orderedBodies = [
      ...stickmen.flatMap((s) => s.composite.bodies),
      ...items.flatMap((c) => c.bodies),
    ];

    this.battleStarted = true;

    const finishStart = () => {
      this.session?.beginBattle();
      this.logEvent(`battle start n=${n}`);
      this.broadcast({
        type: "start",
        fighterIds: stickmen.map((s) => s.fighterId),
      });
      this.broadcastBattleState(true);
      this.startBattleLoops();
    };

    if (this.syncSettle) {
      for (let i = 0; i < SERVER_SETTLE_TICKS; i++) {
        this.session.tick(TICK_MS);
      }
      finishStart();
      return;
    }

    let settled = 0;
    const settleBatch = () => {
      const session = this.session;
      if (!session) return;
      const batchEnd = Math.min(settled + 15, SERVER_SETTLE_TICKS);
      for (; settled < batchEnd; settled++) {
        session.tick(TICK_MS);
      }
      if (settled < SERVER_SETTLE_TICKS) {
        setImmediate(settleBatch);
        return;
      }
      finishStart();
    };
    setImmediate(settleBatch);
  }

  private startBattleLoops(): void {
    const tickMs = TICK_MS;
    let tick = 0;
    this.tickTimer = setInterval(() => {
      const session = this.session;
      if (!session) return;
      session.tick(tickMs);
      if (session.isBattleOver()) this.scheduleRematchReset();
    }, tickMs);

    this.snapshotTimer = setInterval(() => {
      const session = this.session;
      if (!session) return;
      tick++;
      this.broadcast({
        type: "snapshot",
        payload: {
          tick,
          t: performance.now(),
          bodies: Array.from(encodeBodiesOrdered(this.orderedBodies)),
        },
      });
    }, 1000 / 25);

    this.battleStateTimer = setInterval(() => {
      this.broadcastBattleState(false);
    }, 1000 / 10);
  }

  private broadcastBattleState(force: boolean): void {
    const session = this.session;
    if (!session) return;
    const player = this.slots.get("player");
    const opponent = this.slots.get("opponent");

    const hps: Record<string, number> = {};
    for (const f of session.fighters) {
      hps[f.id] = f.hp;
    }

    const battleOver = session.isBattleOver();
    const winner = battleOver ? session.resolveWinner() : null;
    const winnerTeam =
      battleOver && winner
        ? (session.getFighter(winner)?.team ?? null)
        : null;

    const payload = {
      playerHp: session.getHp("player"),
      opponentHp: session.getHp("opponent"),
      battleOver,
      winner: winner as "player" | "opponent" | string | null,
      playerName: player?.name ?? "Fighter",
      opponentName: opponent?.name ?? "Fighter",
      hps,
      winnerTeam,
    };
    const key = JSON.stringify(payload);
    if (!force && key === this.lastBattleState) return;
    this.lastBattleState = key;
    this.broadcast({ type: "battleState", payload });
  }

  private scheduleRematchReset(): void {
    if (this.resetTimer) return;
    this.resetTimer = setTimeout(() => {
      this.resetForRematch();
    }, REMATCH_RESET_MS);
  }

  private resetForRematch(): void {
    this.logEvent("rematch reset");
    if (this.tickTimer) clearInterval(this.tickTimer);
    if (this.snapshotTimer) clearInterval(this.snapshotTimer);
    if (this.battleStateTimer) clearInterval(this.battleStateTimer);
    this.tickTimer = null;
    this.snapshotTimer = null;
    this.battleStateTimer = null;
    this.resetTimer = null;
    this.session?.destroy();
    this.session = null;
    this.battleStarted = false;
    this.lastBattleState = "";
    this.orderedBodies = [];

    for (const [id, client] of this.clients) {
      if (id.endsWith("-slot")) continue;
      client.ready = false;
    }
    for (const slot of this.slots.values()) {
      slot.ready = false;
    }
    this.broadcastLobby();
  }

  private broadcast(msg: unknown): void {
    for (const [id, client] of this.clients) {
      if (id.endsWith("-slot")) continue;
      client.send(msg);
    }
  }

  destroy(): void {
    if (this.resetTimer) clearTimeout(this.resetTimer);
    if (this.tickTimer) clearInterval(this.tickTimer);
    if (this.snapshotTimer) clearInterval(this.snapshotTimer);
    if (this.battleStateTimer) clearInterval(this.battleStateTimer);
    this.session?.destroy();
    this.session = null;
    this.battleStarted = false;
  }
}
