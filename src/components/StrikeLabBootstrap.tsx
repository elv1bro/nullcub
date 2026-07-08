import { GameContext } from "@/GameContext";
import { isStrikeLabMode } from "@/lib/strikeLabMode";
import { useContext, useEffect, useRef } from "react";

/** При ?lab=1 сразу переходит в бой (StrikeLab), без клика в меню. */
export function StrikeLabBootstrap() {
  const { sendN } = useContext(GameContext);
  const startedRef = useRef(false);

  useEffect(() => {
    if (!isStrikeLabMode() || startedRef.current) return;
    startedRef.current = true;
    sendN({ type: "STRIKE_LAB" })();
  }, [sendN]);

  return null;
}
