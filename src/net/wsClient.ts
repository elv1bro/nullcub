import type {
  NetBattleStatePayload,
  NetHitPayload,
  NetInputPayload,
  NetSnapshotPayload,
} from "./protocol";
import type {
  NetTransport,
  WsClientMessage,
  WsLobbyPlayer,
  WsServerMessage,
} from "./transport";

type Handler<T> = (payload: T) => void;

export class WsNetTransport implements NetTransport {
  private ws: WebSocket;
  private inputHandlers = new Set<Handler<NetInputPayload>>();
  private snapshotHandlers = new Set<Handler<NetSnapshotPayload>>();
  private hitHandlers = new Set<Handler<NetHitPayload>>();
  private battleStateHandlers = new Set<Handler<NetBattleStatePayload>>();
  private lobbyHandlers = new Set<Handler<WsLobbyPlayer[]>>();
  private startHandlers = new Set<Handler<void>>();
  private closeHandlers = new Set<(code: number, reason: string) => void>();
  private opponentLeftHandlers = new Set<
    Handler<{ role: "player" | "opponent" }>
  >();

  constructor(
    url: string,
    onWelcome?: (msg: Extract<WsServerMessage, { type: "welcome" }>) => void,
    onError?: (message: string) => void,
  ) {
    this.ws = new WebSocket(url);
    this.ws.addEventListener("message", (event) => {
      let msg: WsServerMessage;
      try {
        msg = JSON.parse(String(event.data)) as WsServerMessage;
      } catch {
        return;
      }
      switch (msg.type) {
        case "welcome":
          onWelcome?.(msg);
          break;
        case "lobby":
          for (const h of this.lobbyHandlers) h(msg.players);
          break;
        case "start":
          for (const h of this.startHandlers) h(undefined);
          break;
        case "snapshot":
          for (const h of this.snapshotHandlers) h(msg.payload);
          break;
        case "battleState":
          for (const h of this.battleStateHandlers) h(msg.payload);
          break;
        case "hit":
          for (const h of this.hitHandlers) h(msg.payload);
          break;
        case "opponent_left":
          for (const h of this.opponentLeftHandlers) h({ role: msg.role });
          break;
        case "error":
          onError?.(msg.message);
          break;
      }
    });
    this.ws.addEventListener("close", (event) => {
      for (const h of this.closeHandlers) {
        h(event.code, event.reason || "connection closed");
      }
    });
    this.ws.addEventListener("error", () => {
      onError?.("websocket error");
    });
  }

  join(roomId: string, name: string, role?: "player" | "opponent"): void {
    this.send(
      role
        ? { type: "join", roomId, name, role }
        : { type: "join", roomId, name },
    );
  }

  sendReady(ready: boolean): void {
    this.send({ type: "ready", ready });
  }

  onLobby(handler: Handler<WsLobbyPlayer[]>): () => void {
    this.lobbyHandlers.add(handler);
    return () => this.lobbyHandlers.delete(handler);
  }

  onStart(handler: () => void): () => void {
    this.startHandlers.add(handler);
    return () => this.startHandlers.delete(handler);
  }

  sendInput(payload: NetInputPayload): void {
    this.send({ type: "input", payload });
  }

  sendSnapshot(payload: NetSnapshotPayload): void {
    this.sendRaw({ type: "snapshot", payload });
  }

  sendHit(payload: NetHitPayload): void {
    this.sendRaw({ type: "hit", payload });
  }

  sendBattleState(payload: NetBattleStatePayload): void {
    this.sendRaw({ type: "battleState", payload });
  }

  onInput(handler: Handler<NetInputPayload>): () => void {
    this.inputHandlers.add(handler);
    return () => this.inputHandlers.delete(handler);
  }

  onSnapshot(handler: Handler<NetSnapshotPayload>): () => void {
    this.snapshotHandlers.add(handler);
    return () => this.snapshotHandlers.delete(handler);
  }

  onHit(handler: Handler<NetHitPayload>): () => void {
    this.hitHandlers.add(handler);
    return () => this.hitHandlers.delete(handler);
  }

  onBattleState(handler: Handler<NetBattleStatePayload>): () => void {
    this.battleStateHandlers.add(handler);
    return () => this.battleStateHandlers.delete(handler);
  }

  onClose(handler: (code: number, reason: string) => void): () => void {
    this.closeHandlers.add(handler);
    return () => this.closeHandlers.delete(handler);
  }

  onOpponentLeft(
    handler: Handler<{ role: "player" | "opponent" }>,
  ): () => void {
    this.opponentLeftHandlers.add(handler);
    return () => this.opponentLeftHandlers.delete(handler);
  }

  get readyState(): number {
    return this.ws.readyState;
  }

  close(): void {
    this.ws.close();
  }

  onOpen(handler: () => void): void {
    if (this.ws.readyState === WebSocket.OPEN) handler();
    else this.ws.addEventListener("open", handler, { once: true });
  }

  private send(msg: WsClientMessage): void {
    if (this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(JSON.stringify(msg));
  }

  private sendRaw(msg: WsServerMessage): void {
    if (this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(JSON.stringify(msg));
  }
}

export function buildWsUrl(base: string, roomId: string): string {
  const url = new URL(base);
  url.searchParams.set("room", roomId);
  return url.toString();
}

/** WS URL по умолчанию — тот же хост, порт 8787 (или VITE_WS_URL). */
export function defaultWsUrl(): string {
  const env = import.meta.env.VITE_WS_URL as string | undefined;
  if (env) return env;
  if (typeof location !== "undefined") {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    return `${proto}//${location.hostname}:8787`;
  }
  return "ws://127.0.0.1:8787";
}

export function randomDuelRoomId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID().replace(/-/g, "").slice(0, 16);
  }
  return Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 10);
}

export function buildDuelCode(serverUrl: string, roomId: string): string {
  const raw = `${serverUrl}|${roomId}`;
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Разрешён ли WS-сервер из duel code (анти-phishing). */
export function isAllowedWsServer(server: string): boolean {
  try {
    const u = new URL(server);
    if (u.protocol !== "ws:" && u.protocol !== "wss:") return false;
    const env = import.meta.env.VITE_WS_URL as string | undefined;
    if (env) {
      const allowed = new URL(env);
      return u.host === allowed.host;
    }
    if (typeof location !== "undefined") {
      if (u.hostname === location.hostname) return true;
      if (u.hostname === "127.0.0.1" || u.hostname === "localhost") return true;
    }
    return u.hostname === "127.0.0.1" || u.hostname === "localhost";
  } catch {
    return false;
  }
}

export function parseDuelCode(code: string): { server: string; room: string } | null {
  const trimmed = code.trim();
  if (!trimmed) return null;
  try {
    const b64 = trimmed.replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64 + "===".slice((b64.length + 3) % 4);
    const raw = atob(pad);
    const sep = raw.indexOf("|");
    if (sep <= 0) return null;
    const server = raw.slice(0, sep);
    const room = raw.slice(sep + 1);
    if (!server || !room) return null;
    if (!isAllowedWsServer(server)) return null;
    return { server, room };
  } catch {
    return null;
  }
}

export function buildDuelShareUrl(code: string): string {
  if (typeof location === "undefined") return `#duel=${code}`;
  return `${location.origin}${location.pathname}#duel=${encodeURIComponent(code)}`;
}

export function parseDuelHash(): { server: string; room: string; code: string } | null {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const code = params.get("duel");
  if (!code) return null;
  const parsed = parseDuelCode(code);
  if (!parsed) return null;
  return { ...parsed, code };
}

export function setDuelHash(code: string): void {
  const url = new URL(window.location.href);
  url.hash = `duel=${encodeURIComponent(code)}`;
  window.history.replaceState(null, "", url.toString());
}

export function parseJoinHash(): {
  server: string | null;
  room: string | null;
  role: "player" | "opponent" | null;
  name: string | null;
} {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const role = params.get("role");
  return {
    server: params.get("server"),
    room: params.get("room"),
    role: role === "player" || role === "opponent" ? role : null,
    name: params.get("name"),
  };
}
