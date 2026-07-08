import type { ServerDebugSnapshot } from "@/server/debugTypes";

export interface RagdollDevConfig {
  mode: "hub" | "client";
  room: string;
  wsPort: number;
  vitePort: number;
  hostJoinUrl: string;
  guestJoinUrl: string;
}

export interface RagdollDevStats extends ServerDebugSnapshot {
  wsRunning: boolean;
}

declare global {
  interface Window {
    ragdollDev?: {
      getConfig: () => Promise<RagdollDevConfig>;
      getServerStats: () => Promise<RagdollDevStats>;
      copyGuestUrl: () => Promise<string>;
      openGuestWindow: () => Promise<string>;
    };
  }
}

export {};
