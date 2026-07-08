import { GameContext } from "@/GameContext";
import { Renderer } from "@/components/Renderer";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { getBattleConfig } from "@/lib/battleConfig";
import { useNetSession } from "@/net/NetSessionContext";
import {
  isNetworkHost,
  networkRole,
  useNetPing,
} from "@/net/useNetBattle";
import { useCallback, useContext, useMemo } from "react";
import { useKeyPressEvent } from "react-use";
import { LeveL1 } from "./LeveL1";
import { NetBattleGuest } from "./NetBattleGuest";

export default function BattleNetwork() {
  const { sendN } = useContext(GameContext);
  const net = useNetSession();
  const config = useMemo(() => getBattleConfig(), []);
  const isHost = networkRole() === "host";
  const pingMs = useNetPing(config.kind === "network");

  const onBack = useCallback(() => sendN("BACK")(), [sendN]);
  useKeyPressEvent("Escape", onBack);

  if (config.kind !== "network") {
    return (
      <section className="h-100% overflow-hidden grid items-center justify-center">
        <Renderer engine={{ gravity: BATTLE_GRAVITY }}>
          <LeveL1 />
        </Renderer>
      </section>
    );
  }

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center">
      <div className="fixed top-2 right-2 z-30 text-xs text-gray-400 font-ui pointer-events-none">
        {isHost ? "HOST" : "GUEST"}
        {pingMs > 0 && ` · ${pingMs}ms`}
        {net.peers.length > 0 && ` · ${net.peers.length} peer(s)`}
      </div>
      <Renderer
        engine={{ gravity: BATTLE_GRAVITY }}
        runner={{ enabled: !isHost }}
      >
        {isHost ? <LeveL1 /> : <NetBattleGuest />}
      </Renderer>
    </section>
  );
}

export { isNetworkHost };
