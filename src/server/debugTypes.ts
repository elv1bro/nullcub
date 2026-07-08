import type { WsLobbyPlayer } from "@/net/transport";

export interface GameRoomDebugInfo {
  roomId: string;
  battleStarted: boolean;
  players: WsLobbyPlayer[];
  playerHp: number | null;
  opponentHp: number | null;
  battleOver: boolean;
  events: string[];
}

/** Меняй при изменении протокола settle/grace — electron проверяет build id. */
export interface ServerDebugSnapshot {
  wsPort: number;
  roomCount: number;
  rooms: GameRoomDebugInfo[];
  serverBuildId: string;
  settleTicks: number;
  spawnGraceMs: number;
}
