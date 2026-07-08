import type { States } from "@/GameContext";
import { lazy } from "react";

export const routes = new Map<States, ReturnType<typeof lazy>>([
  ["idle", lazy(() => import("./Menu"))],
  ["game_type", lazy(() => import("./Menu"))],
  ["play_scope", lazy(() => import("./Menu"))],
  ["campaign_menu", lazy(() => import("./Menu"))],
  ["campaign", lazy(() => import("./Menu"))],
  ["multiplayer_lobby", lazy(() => import("./MultiplayerLobby"))],
  ["workshop", lazy(() => import("./Workshop"))],
  ["battle", lazy(() => import("./BattleRouter"))],
]);
