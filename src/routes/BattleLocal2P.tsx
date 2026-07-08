/**
 * Локальный бой 2 игроков: P1 WASD + Q/E grab, P2 стрелки.
 */
import { GameContext } from "@/GameContext";
import { Renderer } from "@/components/Renderer";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { useCallback, useContext } from "react";
import { useKeyPressEvent } from "react-use";
import { LeveL1 } from "./LeveL1";

export default BattleLocal2P;

export function BattleLocal2P() {
  const { sendN } = useContext(GameContext);

  const onBack = useCallback(() => sendN("BACK")(), [sendN]);
  useKeyPressEvent("Escape", onBack);

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center">
      <Renderer engine={{ gravity: BATTLE_GRAVITY }}>
        <LeveL1 />
      </Renderer>
    </section>
  );
}
