import { getBattleConfig } from "@/lib/battleConfig";
import { lazy, useMemo } from "react";

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
      return <BattleLocal4FFA />;
    case "network":
      return <BattleNetwork />;
    case "dedicated":
      return <BattleDedicated />;
    default:
      return <Battle1Player />;
  }
}
