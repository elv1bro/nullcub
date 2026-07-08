/** Сетевой протокол — типизированные сообщения Trystero makeAction. */

export type NetRole = "host" | "guest";

export interface NetInputPayload {
  seq: number;
  t: number;
  move: { x: number; y: number };
  grabL: boolean;
  grabR: boolean;
  dash: boolean;
  flip: boolean;
  freeze: boolean;
  reset: boolean;
}

export interface NetSnapshotPayload {
  tick: number;
  t: number;
  /** [bodyId, x, y, angle, vx, vy] */
  bodies: Float32Array;
}

export interface NetHitPayload {
  victimId: string;
  damage: number;
  damageType: string;
  x: number;
  y: number;
}

export interface NetGrabPayload {
  fighterId: string;
  hand: "left" | "right";
  attach: boolean;
  targetBodyId?: number;
}

export interface NetEmotionPayload {
  fighterId: string;
  emotion: string;
  intensity: number;
}

export interface NetCropPayload {
  fighterId: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

export type FacePrivacyMode = "video" | "tracking" | "none";

export interface NetMediaStatePayload {
  fighterId: string;
  cam: boolean;
  mic: boolean;
  faceMode: FacePrivacyMode;
}

export interface NetReadyPayload {
  fighterId: string;
  name: string;
  ready: boolean;
}

export interface NetStartMatchPayload {
  roomId: string;
}

/** HP, конец боя — хост → гость (гость = opponent на хосте). */
export interface NetBattleStatePayload {
  playerHp: number;
  opponentHp: number;
  battleOver: boolean;
  winner: "player" | "opponent" | null;
  playerName: string;
  opponentName: string;
}

export const SNAPSHOT_HZ = 25;
export const INPUT_HZ = 30;
export const BATTLE_STATE_HZ = 10;
