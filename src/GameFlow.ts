import { createMachine } from "xstate";

export const GameFlow = createMachine({
  id: "GameFlow",
  initial: "idle",
  schema: {
    events: {} as
      | { type: "BACK" }
      | { type: "PLAY" }
      | { type: "QUICK_BATTLE" }
      | { type: "CAMPAIGN" }
      | { type: "LOCAL_1P" }
      | { type: "LOCAL_2P" }
      | { type: "LOCAL_4FFA" }
      | { type: "LOCAL_CAMPAIGN" }
      | { type: "MULTIPLAYER" }
      | { type: "START_BATTLE" }
      | { type: "STRIKE_LAB" }
      | { type: "WORKSHOP" },
  },
  tsTypes: {} as import("./GameFlow.typegen").Typegen0,
  states: {
    idle: {
      on: {
        PLAY: "game_type",
        STRIKE_LAB: "battle",
        WORKSHOP: "workshop",
      },
    },
    game_type: {
      on: {
        BACK: "idle",
        QUICK_BATTLE: "play_scope",
        CAMPAIGN: "campaign_menu",
        STRIKE_LAB: "battle",
      },
    },
    play_scope: {
      on: {
        BACK: "game_type",
        LOCAL_1P: "battle",
        LOCAL_2P: "battle",
        LOCAL_4FFA: "battle",
        MULTIPLAYER: "play_scope",
        START_BATTLE: "battle",
        STRIKE_LAB: "battle",
      },
    },
    multiplayer_lobby: {
      on: {
        BACK: "play_scope",
        START_BATTLE: "battle",
      },
    },
    campaign_menu: {
      on: {
        BACK: "game_type",
        LOCAL_CAMPAIGN: "campaign",
        MULTIPLAYER: "multiplayer_lobby",
        STRIKE_LAB: "battle",
      },
    },
    campaign: {
      on: {
        BACK: "campaign_menu",
        START_BATTLE: "battle",
        STRIKE_LAB: "battle",
      },
    },
    battle: {
      on: {
        BACK: "idle",
      },
    },
    workshop: {
      on: {
        BACK: "idle",
        START_BATTLE: "battle",
        STRIKE_LAB: "battle",
      },
    },
  },
});
