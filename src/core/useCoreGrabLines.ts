import { getHandBody } from "@/lib/grab/hands";
import type { GrabVisualLine } from "@/lib/grab/types";
import Matter, { type Composite } from "matter-js";
import { useEffect, type MutableRefObject, type RefObject } from "react";
import type { BattleSession } from "./battleSession";

export function useCoreGrabLines(
  sessionRef: RefObject<BattleSession | null>,
  fighterCompositeRef: RefObject<Composite | undefined>,
  fighterId: string,
  linesRef: MutableRefObject<GrabVisualLine[]>,
  enabled: boolean,
): void {
  useEffect(() => {
    if (!enabled) return;
    let raf = 0;
    const tick = () => {
      const session = sessionRef.current;
      const composite = fighterCompositeRef.current;
      const lines: GrabVisualLine[] = [];
      if (session && composite) {
        const st = session.grab.states.get(fighterId);
        if (st) {
          const allBodies = Matter.Composite.allBodies(session.engine.world);
          for (const side of ["left", "right"] as const) {
            const hand = side === "left" ? st.left : st.right;
            if (hand.phase !== "attached" || !hand.target) continue;
            const handBody = getHandBody(composite, side);
            const target = allBodies.find((b) => b.id === hand.target!.bodyId);
            if (!handBody || !target) continue;
            lines.push({
              from: { x: handBody.position.x, y: handBody.position.y },
              to: { x: target.position.x, y: target.position.y },
              hand: side,
              color: "#fbbf24",
            });
          }
        }
      }
      linesRef.current = lines;
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [enabled, sessionRef, fighterCompositeRef, fighterId, linesRef]);
}
