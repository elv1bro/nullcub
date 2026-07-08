import Matter, { Body, Composite } from "matter-js";
import { createStickman } from "@/utils/createStickman";
import { tagStickmanHands } from "@/lib/grab/hands";
import { createArenaWalls } from "@/battle/headlessWalls";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { MAX_HP, OPPONENT_MAX_HP } from "@/lib/combat";
import { createBattleSession, type BattleSession } from "@/core/battleSession";
import { encodeBodiesOrdered } from "@/net/snapshot";
import type { WsLobbyPlayer } from "@/net/transport";
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

export type FighterRole = "player" | "opponent";

export interface RoomClient {
  id: string;
  name: string;
  fighterId: FighterRole;
  send: (msg: unknown) => void;
  limiter: InputRateLimiter;
  ready?: boolean;
}

export interface GameRoomOptions {
  roomId: string;
  arenaSize?: number;
  onEmpty?: () => void;
  debug?: boolean;
  /** Vitest: settle синхронно. Prod: async батчами без блокировки WS. */
  syncSettle?: boolean;
  /** Спавнить оружие на арене (выкл. для idle-stability без item-chip). */
  spawnItems?: boolean;
}

export class GameRoom {
  readonly roomId: string;
  readonly clients = new Map<string, RoomClient>();
  private session: BattleSession | null = null;
  private tickTimer: ReturnType<typeof setInterval> | null = null;
  private snapshotTimer: ReturnType<typeof setInterval> | null = null;
  private battleStateTimer: ReturnType<typeof setInterval> | null = null;
  private readonly arenaSize: number;
  private readonly onEmpty?: () => void;
  private battleStarted = false;
  private lastBattleState = "";
  /** Тела в детерминированном порядке (боец player, боец opponent, предметы) для ordered-snapshot. */
  private orderedBodies: Body[] = [];
  private readonly debug: boolean;
  private readonly syncSettle: boolean;
  private readonly spawnItems: boolean;
  private readonly events: string[] = [];
  private resetTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(opts: GameRoomOptions) {
    this.roomId = opts.roomId;
    this.arenaSize = opts.arenaSize ?? 1000;
    this.debug = opts.debug ?? false;
    this.syncSettle = opts.syncSettle ?? process.env["VITEST"] === "true";
    this.spawnItems = opts.spawnItems ?? true;
    if (opts.onEmpty) this.onEmpty = opts.onEmpty;
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

  addClient(client: RoomClient): FighterRole | null {
    if (this.clients.has(client.id)) return client.fighterId;

    const name =
      typeof client.name === "string"
        ? client.name.replace(/[\u0000-\u001f]/g, "").slice(0, 32) || "Fighter"
        : "Fighter";
    client.name = name;

    const requested = client.fighterId;
    const playerTaken = this.clients.has("player-slot");
    const opponentTaken = this.clients.has("opponent-slot");

    // Хост (player) не отдаём первому случайному join с role=player без слота —
    // если player занят, а просят player → reject (не свапать в opponent молча
    // только когда явно просили player).
    if (requested === "player" && playerTaken) return null;
    if (requested === "opponent" && opponentTaken) return null;

    if (requested === "player" && !playerTaken) {
      client.fighterId = "player";
    } else if (requested === "opponent" && !opponentTaken) {
      client.fighterId = "opponent";
    } else if (!playerTaken && requested !== "opponent") {
      client.fighterId = "player";
    } else if (!opponentTaken) {
      client.fighterId = "opponent";
    } else {
      return null;
    }

    client.ready = false;
    this.clients.set(client.id, client);
    if (client.fighterId === "player") this.clients.set("player-slot", client);
    if (client.fighterId === "opponent") this.clients.set("opponent-slot", client);
    this.logEvent(`join ${client.name} (${client.fighterId})`);
    this.broadcastLobby();
    return client.fighterId;
  }

  setReady(clientId: string, ready: boolean): void {
    const client = this.clients.get(clientId);
    if (!client) return;
    client.ready = ready;
    this.logEvent(`ready ${client.name} → ${ready ? "yes" : "no"}`);
    this.broadcastLobby();
    this.tryStartBattle();
  }

  removeClient(clientId: string): void {
    const client = this.clients.get(clientId);
    if (!client) return;

    const leftRole = client.fighterId;
    const remainingRole = leftRole === "player" ? "opponent" : "player";
    const remainingBefore = this.clients.get(`${remainingRole}-slot`);
    const playerNameBefore =
      (leftRole === "player" ? client.name : remainingBefore?.name) ?? "Fighter";
    const opponentNameBefore =
      (leftRole === "opponent" ? client.name : remainingBefore?.name) ??
      "Fighter";

    this.clients.delete(clientId);
    if (client.fighterId === "player") this.clients.delete("player-slot");
    if (client.fighterId === "opponent") this.clients.delete("opponent-slot");
    this.logEvent(`leave ${client.name} (${client.fighterId})`);

    if (this.battleStarted && this.session && !this.session.isBattleOver()) {
      this.broadcast({
        type: "opponent_left",
        role: leftRole,
      });
      const left = this.session.getFighter(leftRole);
      if (left) left.hp = 0;
      this.broadcast({
        type: "battleState",
        payload: {
          playerHp: this.session.getHp("player"),
          opponentHp: this.session.getHp("opponent"),
          battleOver: true,
          winner: remainingRole as "player" | "opponent",
          playerName: playerNameBefore,
          opponentName: opponentNameBefore,
        },
      });
      this.scheduleRematchReset();
      this.logEvent(`forfeit → ${remainingRole} wins`);
    }

    if (this.clients.size === 0) {
      this.destroy();
      this.onEmpty?.();
      return;
    }
    this.broadcastLobby();
  }

  private lobbyPlayers(): WsLobbyPlayer[] {
    const players: WsLobbyPlayer[] = [];
    for (const [id, client] of this.clients) {
      if (id.endsWith("-slot")) continue;
      players.push({
        fighterId: client.fighterId,
        name: client.name,
        ready: client.ready ?? false,
      });
    }
    return players;
  }

  private broadcastLobby(): void {
    if (this.battleStarted) return;
    this.broadcast({ type: "lobby", players: this.lobbyPlayers() });
  }

  handleInput(clientId: string, raw: unknown): void {
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
    const fighter = session.getFighter(client.fighterId);
    if (!fighter || fighter.hp <= 0) return;
    session.setInput(client.fighterId, input);
  }

  /** Headless tick для тестов (без setInterval). */
  tickBattle(dtMs = TICK_MS): void {
    this.session?.tick(dtMs);
  }

  private tryStartBattle(): void {
    if (this.battleStarted) return;
    const player = this.clients.get("player-slot");
    const opponent = this.clients.get("opponent-slot");
    if (!(player && opponent)) return;
    if (!(player.ready && opponent.ready)) return;

    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: this.arenaSize, y: this.arenaSize },
    ]);
    const walls = createArenaWalls(bounds, this.arenaSize);
    const stickmanLeft = createStickman(
      (1 / 3) * this.arenaSize,
      (1 / 2) * this.arenaSize,
      { render: { visible: false } },
    );
    const stickmanRight = createStickman(
      (2 / 3) * this.arenaSize,
      (1 / 2) * this.arenaSize,
      { render: { visible: false } },
    );
    tagStickmanHands(stickmanLeft, "player");
    tagStickmanHands(stickmanRight, "opponent");
    for (const body of [...stickmanLeft.bodies, ...stickmanRight.bodies]) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }
    const items = this.spawnItems
      ? spawnArenaItems(DEFAULT_ARENA_ITEMS, [...ARENA_ITEM_SPAWN_POSITIONS])
      : [];

    const headLeft = stickmanLeft.bodies.find((b) => b.label === "Head")!;
    const headRight = stickmanRight.bodies.find((b) => b.label === "Head")!;

    this.session = createBattleSession({
      arenaSize: this.arenaSize,
      walls,
      /** gameRoom сам добавляет composite в world — иначе двойной спавн и взрыв физики */
      compositesInWorld: true,
      damageLocked: true,
      spawnGraceMs: SERVER_SPAWN_GRACE_MS,
      fighters: [
        {
          id: "player",
          composite: stickmanLeft,
          head: headLeft,
          maxHp: MAX_HP,
        },
        {
          id: "opponent",
          composite: stickmanRight,
          head: headRight,
          maxHp: OPPONENT_MAX_HP,
        },
      ],
      itemComposites: items,
      playerCompositeId: stickmanLeft.id,
      opponentCompositeId: stickmanRight.id,
      battleStartMs: performance.now(),
    });

    Composite.add(this.session.engine.world, [
      walls,
      stickmanLeft,
      stickmanRight,
      ...items,
    ]);

    this.session.events.on("hit", (hit) => {
      this.broadcast({
        type: "hit",
        payload: {
          victimId:
            hit.victimCompositeId === stickmanLeft.id ? "player" : "opponent",
          damage: hit.damage,
          damageType: hit.damageTypeId ?? "blunt",
          x: hit.x,
          y: hit.y,
        },
      });
    });

    this.orderedBodies = [
      ...stickmanLeft.bodies,
      ...stickmanRight.bodies,
      ...items.flatMap((c) => c.bodies),
    ];

    this.battleStarted = true;

    const finishStart = () => {
      this.session?.beginBattle();
      this.logEvent("battle start");
      this.broadcast({ type: "start" });
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
    const player = this.clients.get("player-slot");
    const opponent = this.clients.get("opponent-slot");
    if (!session || !player || !opponent) return;

    const battleOver = session.isBattleOver();
    const payload = {
      playerHp: session.getHp("player"),
      opponentHp: session.getHp("opponent"),
      battleOver,
      winner: battleOver
        ? (session.resolveWinner() as "player" | "opponent" | null)
        : null,
      playerName: player.name,
      opponentName: opponent.name,
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
