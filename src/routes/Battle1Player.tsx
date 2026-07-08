//

import { GameContext } from "@/GameContext";
import { Renderer } from "@/components/Renderer";
import { closeStrikeLab, isStrikeLabMode } from "@/lib/strikeLabMode";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import debug from "debug";
import { useCallback, useContext } from "react";
import { useKeyPressEvent } from "react-use";
import { LeveL1 } from "./LeveL1";
import { StrikeLab } from "./StrikeLab";

//

export const log = debug("@:routes:Battle1Player");

//

export default Battle1Player;
export function Battle1Player() {
  const { sendN } = useContext(GameContext);

  const onBack = useCallback(() => {
    if (isStrikeLabMode()) closeStrikeLab();
    sendN("BACK")();
  }, [sendN]);

  useKeyPressEvent("Escape", onBack);

  if (isStrikeLabMode()) {
    return (
      <section className="h-100% overflow-hidden grid items-center justify-center">
        <StrikeLab />
      </section>
    );
  }

  return (
    <section className="h-100% overflow-hidden grid items-center justify-center">
      <Renderer engine={{ gravity: BATTLE_GRAVITY }}>
        <LeveL1 />
      </Renderer>
    </section>
  );
}
