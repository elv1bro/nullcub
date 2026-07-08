/** Транспорт-абстракция — Trystero и WS используют один контракт. */

import type {
  NetBattleStatePayload,
  NetHitPayload,
  NetInputPayload,
  NetSnapshotPayload,
} from "./protocol";

export type NetTransportHandler<T> = (payload: T) => void;

export interface NetTransport {
  sendInput(payload: NetInputPayload): void;
  sendSnapshot?(payload: NetSnapshotPayload): void;
  sendHit?(payload: NetHitPayload): void;
  sendBattleState?(payload: NetBattleStatePayload): void;
  onInput(handler: NetTransportHandler<NetInputPayload>): () => void;
  onSnapshot(handler: NetTransportHandler<NetSnapshotPayload>): () => void;
  onHit(handler: NetTransportHandler<NetHitPayload>): () => void;
  onBattleState(handler: NetTransportHandler<NetBattleStatePayload>): () => void;
  close(): void;
}

export interface WsLobbyPlayer {
  fighterId: "player" | "opponent";
  name: string;
  ready: boolean;
}

export type WsServerMessage =
  | { type: "welcome"; roomId: string; fighterId: string; role: "player" | "opponent" }
  | { type: "lobby"; players: WsLobbyPlayer[] }
  | { type: "start" }
  | { type: "snapshot"; payload: NetSnapshotPayload }
  | { type: "battleState"; payload: NetBattleStatePayload }
  | { type: "hit"; payload: NetHitPayload }
  | { type: "error"; message: string }
  | { type: "opponent_left"; role: "player" | "opponent" };

export type WsClientMessage =
  | { type: "join"; roomId: string; name: string; role?: "player" | "opponent" }
  | { type: "ready"; ready: boolean }
  | { type: "input"; payload: NetInputPayload };
