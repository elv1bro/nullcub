import { describe, expect, it } from "vitest";
import {
  AI_DIFFICULTY_ORDER,
  AI_PROFILES,
  campaignAiProfile,
  getAiProfile,
} from "./aiProfiles";
import {
  computeBotMoveIntent,
  createBotBrainState,
} from "./aiLogic";
import { GRAB_ENABLED } from "@/lib/battleTuning";
import { Body, Vector } from "matter-js";
import {
  simulateDuel,
  summarizePresetWinRates,
  AVERAGE_PLAYER_PROXY,
} from "./aiSim";

describe("aiProfiles", () => {
  it("orders difficulty by target win-rate", () => {
    const rates = AI_DIFFICULTY_ORDER.map(
      (id) => AI_PROFILES[id].targetBotWinRate,
    );
    for (let i = 1; i < rates.length; i++) {
      expect(rates[i]).toBeGreaterThan(rates[i - 1]!);
    }
  });

  it("maps campaign chapters to presets", () => {
    expect(campaignAiProfile(0).id).toBe("easy");
    expect(campaignAiProfile(1).id).toBe("normal");
    expect(campaignAiProfile(3).id).toBe("hard");
    expect(campaignAiProfile(99).id).toBe("boss");
  });

  it("normal preset matches ~20% bot win target", () => {
    expect(getAiProfile("normal").targetBotWinRate).toBe(0.2);
  });

  it.skipIf(!GRAB_ENABLED)("hard/boss unlock grab and dash", () => {
    expect(getAiProfile("normal").grabRange).toBeGreaterThan(0);
    expect(getAiProfile("hard").useDash).toBe(true);
    expect(getAiProfile("boss").useBrace).toBe(true);
  });
});

describe("aiLogic", () => {
  it("returns movement toward player", () => {
    const profile = getAiProfile("normal");
    const state = createBotBrainState();
    const bot = Body.create({ position: { x: 100, y: 500 } });
    const player = Body.create({ position: { x: 400, y: 500 } });
    const intent = computeBotMoveIntent(
      profile,
      state,
      bot,
      player,
      undefined,
      performance.now(),
    );
    expect(intent.worldMove.x).toBeGreaterThan(0.5);
    expect(Vector.magnitude(intent.worldMove)).toBeCloseTo(1, 5);
  });

  it.skipIf(!GRAB_ENABLED)("hard profile can trigger grab flags", () => {
    const profile = { ...getAiProfile("hard"), grabChance: 1 };
    const state = createBotBrainState();
    state.battleStartMs = 0;
    state.grabCooldownUntil = 0;
    const bot = Body.create({ position: { x: 200, y: 500 } });
    const player = Body.create({ position: { x: 255, y: 500 } });
    const intent = computeBotMoveIntent(
      profile,
      state,
      bot,
      player,
      undefined,
      3000,
    );
    expect(intent.grabL || intent.grabR).toBe(true);
  });
});

describe("aiSim", () => {
  it("runs offline duels and reports rates", () => {
    const result = simulateDuel(getAiProfile("normal"), AVERAGE_PLAYER_PROXY, 5);
    expect(result.botWins + result.playerWins + result.draws).toBe(5);
    expect(result.botWinRate).toBeGreaterThanOrEqual(0);
    expect(result.botWinRate).toBeLessThanOrEqual(1);
  });

  it("summarizePresetWinRates covers all presets", () => {
    const summary = summarizePresetWinRates(8);
    for (const id of AI_DIFFICULTY_ORDER) {
      expect(summary[id]?.target).toBe(AI_PROFILES[id].targetBotWinRate);
      expect(summary[id]?.simulated).toBeGreaterThanOrEqual(0);
    }
  });
});
