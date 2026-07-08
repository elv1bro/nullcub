import { useMemo } from "react";
import { Renderer } from "@/components/Renderer";
import { useWindowViewport } from "@/components/useWindowViewport";
import { MenuArenaScene, type MenuPlayPhase } from "./MenuArenaScene";

interface Props {
  playPhase: MenuPlayPhase;
  playRunId: number;
  chainsBroken: number;
}

/** Полноэкранная арена меню — Matter.js на весь viewport. */
export function MenuArena({ playPhase, playRunId, chainsBroken }: Props) {
  const [width, height] = useWindowViewport();

  const renderOptions = useMemo(
    () => ({
      options: {
        width,
        height,
        background: "#0c0c14",
        wireframes: false,
      },
    }),
    [width, height],
  );

  return (
    <div className="menu-arena-canvas-wrap absolute inset-0">
      <Renderer render={renderOptions}>
        <MenuArenaScene
          playPhase={playPhase}
          playRunId={playRunId}
          chainsBroken={chainsBroken}
        />
      </Renderer>
    </div>
  );
}
