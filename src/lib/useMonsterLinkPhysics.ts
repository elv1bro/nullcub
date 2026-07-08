import { useEventBeforeUpdate } from "@1.framework/matter4react";
import { updateMonsterRopeConstraints } from "@/monster/linkTypes";
import type { Composite } from "matter-js";

/** Обновляет верёвки (макс. длина, провисание) каждый кадр. */
export function useMonsterLinkPhysics(
  composite: Composite | undefined | null,
  enabled = true,
): void {
  useEventBeforeUpdate(() => {
    if (!enabled || !composite) return;
    updateMonsterRopeConstraints(composite);
  }, [composite, enabled]);
}
