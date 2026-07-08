import { GameContext } from "@/GameContext";
import { Renderer } from "@/components/Renderer";
import { getBattleConfig } from "@/lib/battleConfig";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { useWsSession } from "@/net/WsSessionContext";
import { DedicatedBattleView } from "@/routes/DedicatedBattleView";
import { useCallback, useContext, useMemo } from "react";
import { useKeyPressEvent } from "react-use";

export default function BattleDedicated() {
  const { sendN } = useContext(GameContext);
  const ws = useWsSession();
  const config = useMemo(() => getBattleConfig(), []);

  const fighterRole =
    config.kind === "dedicated"
      ? config.role === "host"
        ? ("player" as const)
        : ("opponent" as const)
      : ws.role ?? "opponent";

  const onBack = useCallback(() => {
    ws.disconnect();
    sendN("BACK")();
  }, [sendN, ws]);

  useKeyPressEvent("Escape", onBack);

  if (!ws.transport) {
    return (
      <div className="h-full flex items-center justify-center text-gray-400">
        Нет соединения с сервером…
      </div>
    );
  }

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center">
      <Renderer engine={{ gravity: BATTLE_GRAVITY }} runner={{ enabled: false }}>
        <DedicatedBattleView
          transport={ws.transport}
          fighterRole={fighterRole}
          onBack={onBack}
        />
      </Renderer>
    </section>
  );
}
