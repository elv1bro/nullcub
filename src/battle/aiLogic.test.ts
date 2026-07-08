import { describe, expect, it } from "vitest";
import { Body } from "matter-js";
import { getAiProfile } from "./aiProfiles";
import {
  computeBotMoveIntent,
  createBotBrainState,
} from "./aiLogic";
import { BATTLE_OPENING_BRAWL_MS, GRAB_ENABLED } from "@/lib/battleTuning";

describe.skipIf(!GRAB_ENABLED)("aiLogic grab", () => {
  it("releases grab after short hold pulse", () => {
    const profile = getAiProfile("hard");
    const state = createBotBrainState();
    state.battleStartMs = 0;
    state.grabCooldownUntil = 0;
    state.grabSide = "left";
    state.grabUntil = 500;

    const bot = Body.create({ position: { x: 200, y: 500 } });
    const player = Body.create({ position: { x: 240, y: 500 } });

    expect(
      computeBotMoveIntent(profile, state, bot, player, undefined, 400).grabL,
    ).toBe(true);
    expect(
      computeBotMoveIntent(profile, state, bot, player, undefined, 501).grabL,
    ).toBe(false);
  });

  it("does not grab during opening brawl window", () => {
    const profile = getAiProfile("boss");
    const state = createBotBrainState();
    state.battleStartMs = 0;
    state.grabCooldownUntil = 0;

    const bot = Body.create({ position: { x: 200, y: 500 } });
    const player = Body.create({ position: { x: 240, y: 500 } });

    let grabbed = false;
    for (let t = 0; t < BATTLE_OPENING_BRAWL_MS; t += 16) {
      const intent = computeBotMoveIntent(
        profile,
        state,
        bot,
        player,
        undefined,
        t,
      );
      if (intent.grabL || intent.grabR) grabbed = true;
    }
    expect(grabbed).toBe(false);
  });
});
