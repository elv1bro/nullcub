import { randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import type { WsClientMessage } from "@/net/transport";
import { registerDefaultItems } from "@/items";
import { GameRoom } from "./gameRoom";
import type { ServerDebugSnapshot } from "./debugTypes";
import {
  SERVER_BUILD_ID,
  SERVER_SETTLE_TICKS,
  SERVER_SPAWN_GRACE_MS,
} from "./serverConstants";
import { InputRateLimiter } from "./inputValidator";

registerDefaultItems();

const rooms = new Map<string, GameRoom>();
let serverDebugEnabled = false;
let wsPort = Number(process.env["PORT"] ?? 8787);

const MAX_ROOMS = Number(process.env["MAX_ROOMS"] ?? 64);
const MAX_PAYLOAD = 64 * 1024;
const BIND_HOST = process.env["WS_HOST"] ?? "127.0.0.1";
const SECRET_RE = /^[a-f0-9]{16}$/i;

export type { ServerDebugSnapshot } from "./debugTypes";

export function getServerDebugSnapshot(): ServerDebugSnapshot {
  const roomList = [];
  for (const room of rooms.values()) {
    roomList.push(room.getDebugInfo());
  }
  return {
    wsPort,
    roomCount: roomList.length,
    rooms: roomList,
    serverBuildId: SERVER_BUILD_ID,
    settleTicks: SERVER_SETTLE_TICKS,
    spawnGraceMs: SERVER_SPAWN_GRACE_MS,
  };
}

function getOrCreateRoom(roomId: string, secret: string): GameRoom | null {
  const existing = rooms.get(roomId);
  if (existing) {
    if (!existing.matchesSecret(secret)) return null;
    return existing;
  }
  if (rooms.size >= MAX_ROOMS) return null;
  const room = new GameRoom({
    roomId,
    secret,
    debug: serverDebugEnabled,
    onEmpty: () => rooms.delete(roomId),
  });
  rooms.set(roomId, room);
  return room;
}

function send(ws: WebSocket, msg: unknown): void {
  if (ws.readyState !== ws.OPEN) return;
  ws.send(JSON.stringify(msg));
}

export function startGameServer(
  port = Number(process.env["PORT"] ?? 8787),
  options?: { debug?: boolean; debugHttpPort?: number; host?: string },
) {
  wsPort = port;
  serverDebugEnabled = options?.debug ?? false;
  const host = options?.host ?? BIND_HOST;
  const wss = new WebSocketServer({ port, host, maxPayload: MAX_PAYLOAD });

  let debugHttp: ReturnType<typeof createServer> | null = null;
  if (options?.debugHttpPort) {
    debugHttp = createServer((req, res) => {
      if (req.url === "/debug") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(getServerDebugSnapshot()));
        return;
      }
      res.writeHead(404);
      res.end();
    });
    debugHttp.listen(options.debugHttpPort, "127.0.0.1");
  }

  wss.on("connection", (ws, req) => {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    const roomParam = url.searchParams.get("room");
    const clientId = randomUUID();
    let joinedRoom: GameRoom | null = null;

    ws.on("message", (raw) => {
      try {
        let msg: WsClientMessage;
        try {
          msg = JSON.parse(String(raw)) as WsClientMessage;
        } catch {
          send(ws, { type: "error", message: "invalid json" });
          return;
        }

        if (msg.type === "join") {
          const roomId = (msg.roomId || roomParam || "").trim();
          const secret =
            typeof msg.secret === "string" ? msg.secret.trim().toLowerCase() : "";
          if (!roomId || roomId === "default") {
            send(ws, { type: "error", message: "room id required" });
            return;
          }
          if (roomId.length > 64) {
            send(ws, { type: "error", message: "room id too long" });
            return;
          }
          if (!SECRET_RE.test(secret)) {
            send(ws, { type: "error", message: "room secret required" });
            return;
          }
          const room = getOrCreateRoom(roomId, secret);
          if (!room) {
            const exists = rooms.has(roomId);
            send(ws, {
              type: "error",
              message: exists ? "invalid room secret" : "server full",
            });
            return;
          }
          joinedRoom = room;
          const fighterId = joinedRoom.addClient({
            id: clientId,
            name: msg.name || "Fighter",
            fighterId: msg.role ?? "player",
            ownedFighterIds: [],
            send: (payload) => send(ws, payload),
            limiter: new InputRateLimiter(),
          });
          if (!fighterId) {
            send(ws, { type: "error", message: "room full" });
            return;
          }
          const client = joinedRoom.clients.get(clientId);
          send(ws, {
            type: "welcome",
            roomId,
            fighterId,
            role: fighterId,
            ownedFighterIds: client?.ownedFighterIds ?? [fighterId],
          });
          return;
        }

        if (msg.type === "battleMode") {
          if (!joinedRoom) {
            send(ws, { type: "error", message: "join first" });
            return;
          }
          const mode = msg.mode === "partyBots" ? "partyBots" : "ffa";
          const diff =
            msg.difficulty === "easy" ||
            msg.difficulty === "normal" ||
            msg.difficulty === "hard" ||
            msg.difficulty === "boss"
              ? msg.difficulty
              : undefined;
          joinedRoom.setBattleMode(mode, diff);
          return;
        }

        if (msg.type === "ready") {
          if (!joinedRoom) {
            send(ws, { type: "error", message: "join first" });
            return;
          }
          joinedRoom.setReady(clientId, Boolean(msg.ready));
          return;
        }

        if (msg.type === "claimLocal") {
          if (!joinedRoom) {
            send(ws, { type: "error", message: "join first" });
            return;
          }
          const localId = joinedRoom.claimLocal(
            clientId,
            typeof msg.name === "string" ? msg.name : "P2",
          );
          if (!localId) {
            send(ws, { type: "error", message: "cannot claim local slot" });
            return;
          }
          const client = joinedRoom.clients.get(clientId);
          send(ws, {
            type: "welcome",
            roomId: joinedRoom.roomId,
            fighterId: client?.fighterId ?? "player",
            role: client?.fighterId ?? "player",
            ownedFighterIds: client?.ownedFighterIds ?? [],
          });
          return;
        }

        if (msg.type === "releaseLocal") {
          if (!joinedRoom) return;
          joinedRoom.releaseLocal(clientId, String(msg.fighterId ?? ""));
          return;
        }

        if (msg.type === "input") {
          if (!joinedRoom) {
            send(ws, { type: "error", message: "join first" });
            return;
          }
          joinedRoom.handleInput(
            clientId,
            msg.payload,
            typeof msg.fighterId === "string" ? msg.fighterId : undefined,
          );
        }
      } catch (err) {
        console.error("[server] message handler error", err);
        send(ws, { type: "error", message: "internal error" });
      }
    });

    ws.on("close", () => {
      joinedRoom?.removeClient(clientId);
    });
  });

  const closeAll = () => {
    debugHttp?.close();
    wss.close();
  };
  (wss as WebSocketServer & { closeAll?: () => void }).closeAll = closeAll;

  return wss;
}

const isDirectRun =
  process.argv[1]?.includes("server/main") ||
  process.argv[1]?.endsWith("main.ts");

if (isDirectRun) {
  const port = Number(process.env["PORT"] ?? 8787);
  const debug = process.env["RAGDOLL_DEBUG"] === "1";
  const debugHttpPort = Number(process.env["DEBUG_HTTP_PORT"] ?? port + 1);
  startGameServer(port, {
    debug,
    ...(debug ? { debugHttpPort } : {}),
  });
  console.log(`[server] WS listening on ws://${BIND_HOST}:${port}`);
  if (debug) {
    console.log(`[server] debug http://127.0.0.1:${debugHttpPort}/debug`);
  }
}
