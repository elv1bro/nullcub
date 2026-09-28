/** Транспорт-абстракция — Trystero и WS используют один контракт. */

import type {
  NetBattleStatePayload,
  NetHitPayload,
  NetInputPayload,
  NetSnapshotPayload,
} from "./protocol";

export type NetTransportHandler<T> = (payload: T) => void;

export interface NetTransport {
  sendInput(payload: NetInputPayload, fighterId?: string): void;
  sendSnapshot?(payload: NetSnapshotPayload): void;
  sendHit?(payload: NetHitPayload): void;
  sendBattleState?(payload: NetBattleStatePayload): void;
  onInput(handler: NetTransportHandler<NetInputPayload>): () => void;
  onSnapshot(handler: NetTransportHandler<NetSnapshotPayload>): () => void;
  onHit(handler: NetTransportHandler<NetHitPayload>): () => void;
  onBattleState(handler: NetTransportHandler<NetBattleStatePayload>): () => void;
  close(): void;
}

export const WS_MAX_SLOTS = 4;

export type WsFighterId = "player" | "opponent" | "p2" | "p3";

export interface WsLobbyPlayer {
  fighterId: WsFighterId | string;
  name: string;
  ready: boolean;
  /** Команда (0/1) для 2v2; в FFA у каждого своя. */
  team?: number;
  /** Клиент, владеющий слотом (для локального второго игрока). */
  ownerClientId?: string;
}

export type WsServerMessage =
  | {
      type: "welcome";
      roomId: string;
      fighterId: string;
      role: "player" | "opponent" | string;
      /** Все fighterId, которыми владеет этот сокет (хост + локальный). */
      ownedFighterIds?: string[];
    }
  | { type: "lobby"; players: WsLobbyPlayer[] }
  | { type: "start"; fighterIds?: string[] }
  | { type: "snapshot"; payload: NetSnapshotPayload }
  | { type: "battleState"; payload: NetBattleStatePayload }
  | { type: "hit"; payload: NetHitPayload }
  | { type: "error"; message: string }
  | { type: "opponent_left"; role: string };

export type WsClientMessage =
  | {
      type: "join";
      roomId: string;
      name: string;
      /** Секрет комнаты из duel code — обязателен для join. */
      secret: string;
      role?: "player" | "opponent" | string;
    }
  | { type: "ready"; ready: boolean }
  | {
      type: "input";
      payload: NetInputPayload;
      /** Какой боец получает ввод (для сокета с 2 локальными). */
      fighterId?: string;
    }
  | {
      /** Добавить локального второго игрока на свободный слот. */
      type: "claimLocal";
      name: string;
    }
  | { type: "releaseLocal"; fighterId: string }
  | {
      /** Хост: режим старта комнаты (FFA / пати vs 1 бот). */
      type: "battleMode";
      mode: "ffa" | "partyBots";
      difficulty?: "easy" | "normal" | "hard" | "boss";
    };
