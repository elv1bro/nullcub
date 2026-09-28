//

import { GameContext } from "@/GameContext";
import { Renderer } from "@/components/Renderer";
import { getBattleConfig } from "@/lib/battleConfig";
import { closeStrikeLab, isStrikeLabMode } from "@/lib/strikeLabMode";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import debug from "debug";
import { useCallback, useContext, useMemo } from "react";
import { useKeyPressEvent } from "react-use";
import { LeveL1 } from "./LeveL1";
import { StrikeLab } from "./StrikeLab";

//

export const log = debug("@:routes:Battle1Player");

//

export default Battle1Player;
export function Battle1Player() {
  const { sendN } = useContext(GameContext);
  const battleKind = useMemo(() => getBattleConfig().kind, []);

  const onBack = useCallback(() => {
    if (isStrikeLabMode()) closeStrikeLab();
    sendN("BACK")();
  }, [sendN]);

  useKeyPressEvent("Escape", onBack);

  // Каталог / тест-арена всегда идут в обычный бой, даже если в URL ещё ?lab=…
  const showStrikeLab =
    isStrikeLabMode() &&
    battleKind !== "lab" &&
    battleKind !== "testArena";

  if (showStrikeLab) {
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
