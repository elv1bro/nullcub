import { joinRoom } from "trystero/nostr";
import type { Room } from "trystero";
import type {
  NetBattleStatePayload,
  NetCropPayload,
  NetEmotionPayload,
  NetGrabPayload,
  NetHitPayload,
  NetInputPayload,
  NetMediaStatePayload,
  NetReadyPayload,
  NetSnapshotPayload,
  NetStartMatchPayload,
} from "./protocol";

export type NetRoom = Room;

/** Trystero 0.25+: makeAction → { send, onMessage }. Совместимость с [send, on]. */
export type NetActionSend<T> = (data: T, peerIds?: string[]) => void;
export type NetActionOn<T> = (handler: (data: T, peerId: string) => void) => void;
export type NetActionPair<T> = [NetActionSend<T>, NetActionOn<T>];

/** Форма объекта, который возвращает makeAction (типы trystero требуют
 * DataPayload, а наши payload-интерфейсы структурно совместимы с JSON). */
interface RawNetAction<T> {
  send: (data: T, options?: { target: string }) => Promise<unknown> | void;
  onMessage: ((data: T, meta: { peerId: string }) => void) | null;
}

function makeNetAction<T>(room: NetRoom, actionId: string): NetActionPair<T> {
  const action = room.makeAction(actionId) as unknown as RawNetAction<T>;
  const send: NetActionSend<T> = (data, peerIds = []) => {
    if (peerIds.length === 0) {
      void action.send(data);
      return;
    }
    for (const target of peerIds) {
      void action.send(data, { target });
    }
  };
  const on: NetActionOn<T> = (handler) => {
    action.onMessage = (data, { peerId }) => {
      void handler(data as T, peerId);
    };
  };
  return [send, on];
}

export function createNetRoom(roomId: string): NetRoom {
  return joinRoom({ appId: "ragdoll-faces" }, roomId);
}

export function wireNetActions(room: NetRoom) {
  return {
    input: makeNetAction<NetInputPayload>(room, "input"),
    snapshot: makeNetAction<NetSnapshotPayload>(room, "snapshot"),
    hit: makeNetAction<NetHitPayload>(room, "hit"),
    grab: makeNetAction<NetGrabPayload>(room, "grab"),
    emotion: makeNetAction<NetEmotionPayload>(room, "emotion"),
    crop: makeNetAction<NetCropPayload>(room, "crop"),
    mediaState: makeNetAction<NetMediaStatePayload>(room, "mediaState"),
    ready: makeNetAction<NetReadyPayload>(room, "ready"),
    battleState: makeNetAction<NetBattleStatePayload>(room, "battleState"),
    startMatch: makeNetAction<NetStartMatchPayload>(room, "startMatch"),
  };
}

export function getRoomIdFromHash(): string | null {
  const hash = window.location.hash.slice(1);
  const params = new URLSearchParams(hash);
  return params.get("room");
}

export function setRoomHash(roomId: string): void {
  const url = new URL(window.location.href);
  url.hash = `room=${roomId}`;
  window.history.replaceState(null, "", url.toString());
}

export function randomRoomId(): string {
  return Math.random().toString(36).slice(2, 10);
}
