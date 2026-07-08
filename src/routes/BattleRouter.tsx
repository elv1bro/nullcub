import { getBattleConfig } from "@/lib/battleConfig";
import { ENABLE_LOCAL_FFA, ENABLE_P2P } from "@/lib/featureFlags";
import { lazy, useMemo } from "react";
import { BattleUnavailable } from "./BattleUnavailable";

const Battle1Player = lazy(() => import("./Battle1Player"));
const BattleLocal2P = lazy(() => import("./BattleLocal2P"));
const BattleLocal4FFA = lazy(() => import("./BattleLocal4FFA"));
const BattleNetwork = lazy(() => import("./BattleNetwork"));
const BattleDedicated = lazy(() => import("./BattleDedicated"));

export default function BattleRouter() {
  const config = useMemo(() => getBattleConfig(), []);

  switch (config.kind) {
    case "local2p":
      return <BattleLocal2P />;
    case "local4ffa":
      if (!ENABLE_LOCAL_FFA) {
        return (
          <BattleUnavailable reason="4FFA на legacy useRosterHealth отключён. Включите VITE_ENABLE_LOCAL_FFA=1 или играйте 1v1 / WS-дуэль." />
        );
      }
      return <BattleLocal4FFA />;
    case "network":
      if (!ENABLE_P2P) {
        return (
          <BattleUnavailable reason="P2P (Trystero) отключён — хост полностью trusted. Онлайн: WS-дуэль из меню. Флаг: VITE_ENABLE_P2P=1." />
        );
      }
      return <BattleNetwork />;
    case "dedicated":
      return <BattleDedicated />;
    default:
      return <Battle1Player />;
  }
}
