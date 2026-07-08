import { describe, expect, it } from "vitest";
import { createBattleSession, emptyInput, tickFighterAbilities } from "@/core";
import { createAbilityState } from "@/core/abilityTick";
import { createStickman } from "@/utils/createStickman";
import { tagStickmanHands } from "@/lib/grab/hands";
import { capturePoseSnapshot } from "@/lib/ragdollPoseReset";
import { MAX_HP } from "@/lib/combat";
import { FLIP_COOLDOWN_MS } from "@/lib/battleTuning";
import Matter from "matter-js";

describe("ability one-shot flags", () => {
  it("flip does not retrigger every tick while input.flip stays true without cooldown wait", () => {
    const a = createStickman(300, 500, { render: { visible: false } });
    tagStickmanHands(a, "player");
    const head = a.bodies.find((b) => b.label === "Head")!;
    const session = createBattleSession({
      arenaSize: 1000,
      fighters: [
        { id: "player", composite: a, head, maxHp: MAX_HP },
      ],
      playerCompositeId: a.id,
    });
    session.beginBattle();

    const fighter = session.getFighter("player")!;
    const ability = session.getAbilityState("player")!;
    const event = { delta: 16 } as Matter.IEventTimestamped<Matter.Engine>;

    fighter.input = { ...emptyInput(), flip: true };
    tickFighterAbilities(fighter, ability, event, performance.now(), () => 0.5);
    const firstFlipAt = ability.lastFlip;
    expect(firstFlipAt).toBeGreaterThan(0);

    // Тот же кадр+сразу: кулдаун не прошёл — не должно обновить lastFlip
    tickFighterAbilities(
      fighter,
      ability,
      event,
      firstFlipAt + 10,
      () => 0.5,
    );
    expect(ability.lastFlip).toBe(firstFlipAt);

    // После кулдауна при всё ещё true — сработает снова (level-trigger).
    // Поэтому клиент обязан consume flags (useCoreInputBridge).
    tickFighterAbilities(
      fighter,
      ability,
      event,
      firstFlipAt + FLIP_COOLDOWN_MS + 1,
      () => 0.5,
    );
    expect(ability.lastFlip).toBeGreaterThan(firstFlipAt);

    session.destroy();
  });

  it("consume pattern: clearing flags prevents second flip", () => {
    const flags = { dash: false, flip: true, freeze: false, reset: false };
    const snap = { ...flags };
    flags.flip = false; // consume
    expect(snap.flip).toBe(true);
    expect(flags.flip).toBe(false);

    const a = createStickman(300, 500, { render: { visible: false } });
    const head = a.bodies.find((b) => b.label === "Head")!;
    const ability = createAbilityState(capturePoseSnapshot(a));
    const fighter = {
      id: "player",
      composite: a,
      head,
      maxHp: MAX_HP,
      hp: MAX_HP,
      input: { ...emptyInput(), flip: snap.flip },
      moveSpeedMult: 1,
      inputBlocked: false,
      braceActive: false,
    };
    const event = { delta: 16 } as Matter.IEventTimestamped<Matter.Engine>;
    const t0 = 1000;
    tickFighterAbilities(fighter, ability, event, t0, () => 0.5);
    const afterFirst = ability.lastFlip;

    fighter.input = { ...emptyInput(), flip: flags.flip }; // consumed = false
    tickFighterAbilities(
      fighter,
      ability,
      event,
      t0 + FLIP_COOLDOWN_MS + 50,
      () => 0.5,
    );
    expect(ability.lastFlip).toBe(afterFirst);
  });
});
