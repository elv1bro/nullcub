import type { AiProfile } from "@/battle/aiProfiles";
import { campaignAiProfile, getAiProfile } from "@/battle/aiProfiles";
import {
  getBouncerChapter,
  pickL10n,
  type BouncerChapter,
} from "@/campaign/bouncer";
import { buildMonster, settleComposite } from "@/monster/buildMonster";
import { getMonster } from "@/monster/monsterStore";
import { normalizeMonsterDef, resolveMonsterDefense } from "@/monster/monsterTypes";
import type { Language } from "@/i18n/types";
import { bodyColorsFromAvatar } from "@/face/bodyColorsFromAvatar";
import {
  avatarFaceIdForSeed,
  getAvatarFacePreset,
  isValidAvatarFaceId,
} from "@/face/avatarPresets";
import type { FighterColors } from "@/lib/fighterColors";
import { OPPONENT_MAX_HP } from "@/lib/combat";
import { battleSpawnPositions } from "@/lib/battleTuning";
import { createStickman } from "@/utils/createStickman";
import type { Composite } from "matter-js";
import type { BattleConfig } from "./battleConfig";

export interface OpponentSpec {
  composite: Composite;
  headLabel: "Head";
  name: string;
  maxHp: number;
  colors: FighterColors;
  /** Пресет-лицо бота (quick / кампания); тело красится в тон палитры. */
  avatarFaceId?: string;
  aiSpeedMult: number;
  aiProfile: AiProfile | null;
  isMonster: boolean;
  defense?: number;
  campaignChapter?: BouncerChapter;
}

function opponentAvatarSeed(config: BattleConfig): string {
  if (config.kind === "campaign") return `campaign-${config.chapterId}`;
  return "quick-opponent";
}

function devBotFaceOverride(): string | undefined {
  if (typeof window === "undefined") return undefined;
  const id = new URLSearchParams(window.location.search).get("botFace");
  if (!id || !isValidAvatarFaceId(id)) return undefined;
  return id;
}

function botAppearanceFromSeed(seed: string): {
  avatarFaceId: string;
  colors: FighterColors;
} {
  const avatarFaceId = devBotFaceOverride() ?? avatarFaceIdForSeed(seed);
  const colors = bodyColorsFromAvatar(getAvatarFacePreset(avatarFaceId));
  return { avatarFaceId, colors };
}

export function resolveBattleOpponent(
  config: BattleConfig,
  arenaSize: number,
  language: Language,
): OpponentSpec {
  const { opponentX: spawnX, y: spawnY } = battleSpawnPositions(arenaSize);

  if (config.kind === "campaign") {
    const chapter = getBouncerChapter(config.chapterId);
    if (!chapter) {
      return defaultQuickOpponent(spawnX, spawnY, language, undefined);
    }

    const { avatarFaceId, colors } = botAppearanceFromSeed(
      opponentAvatarSeed(config),
    );
    const composite = createStickman(spawnX, spawnY, {
      scale: chapter.enemy.scale,
      render: { fillStyle: colors.main },
    });

    const base = campaignAiProfile(chapter.order);
    const profile = { ...base, speedMult: chapter.enemy.aiSpeedMult };

    return {
      composite,
      headLabel: "Head",
      name: pickL10n(chapter.enemy.name, language),
      // База как у игрока; дальше по главам chapter.enemy.hp чуть растёт.
      maxHp: Math.max(OPPONENT_MAX_HP, chapter.enemy.hp),
      colors,
      avatarFaceId,
      aiSpeedMult: profile.speedMult,
      aiProfile: profile,
      isMonster: false,
      campaignChapter: chapter,
    };
  }

  if (config.kind === "local2p") {
    const composite = createStickman(spawnX, spawnY, {
      render: { fillStyle: "#c084fc" },
    });
    return {
      composite,
      headLabel: "Head",
      name: language === "ru" ? "Игрок 2" : "Player 2",
      maxHp: OPPONENT_MAX_HP,
      colors: { main: "#c084fc", secondary: "#7c3aed" },
      aiSpeedMult: 0,
      aiProfile: null,
      isMonster: false,
    };
  }

  if (config.kind === "network") {
    const composite = createStickman(spawnX, spawnY, {
      render: { fillStyle: "#c084fc" },
    });
    return {
      composite,
      headLabel: "Head",
      name: language === "ru" ? "Гость" : "Guest",
      maxHp: OPPONENT_MAX_HP,
      colors: { main: "#c084fc", secondary: "#7c3aed" },
      aiSpeedMult: 0,
      aiProfile: null,
      isMonster: false,
    };
  }

  if (config.kind === "monster") {
    const raw = getMonster(config.monsterId);
    if (!raw) {
      return defaultQuickOpponent(spawnX, spawnY, language, undefined);
    }

    const def = normalizeMonsterDef(raw);
    const built = buildMonster(def, spawnX, spawnY);
    if (!built) {
      return defaultQuickOpponent(spawnX, spawnY, language, undefined);
    }

    settleComposite(built.composite);

    const head = built.composite.bodies.find((b) => b.label === "Head");
    if (head) head.render.visible = false;

    return {
      composite: built.composite,
      headLabel: "Head",
      name: def.name,
      maxHp: built.maxHp,
      colors: built.colors,
      aiSpeedMult: getAiProfile("hard").speedMult,
      aiProfile: getAiProfile("hard"),
      isMonster: true,
      defense: resolveMonsterDefense(def),
    };
  }

  if (config.kind === "roguelike") {
    const profile = getAiProfile(config.difficulty);
    const { avatarFaceId, colors } = botAppearanceFromSeed(
      `rl-f${config.floor}-b${config.bots}`,
    );
    const composite = createStickman(spawnX, spawnY, {
      scale: config.difficulty === "boss" ? 1.15 : 1,
      render: { fillStyle: colors.main },
    });
    const hpScale =
      1 + (config.floor - 1) * 0.12 + Math.max(0, config.bots - 2) * 0.08;
    return {
      composite,
      headLabel: "Head",
      name:
        language === "ru"
          ? `Рогалик · этаж ${config.floor}`
          : `Roguelike · floor ${config.floor}`,
      maxHp: Math.round(OPPONENT_MAX_HP * hpScale),
      colors,
      avatarFaceId,
      aiSpeedMult: profile.speedMult,
      aiProfile: profile,
      isMonster: false,
    };
  }

  const quickHp =
    config.kind === "quick" ? config.opponentHp : undefined;
  return defaultQuickOpponent(spawnX, spawnY, language, quickHp);
}

function defaultQuickOpponent(
  spawnX: number,
  spawnY: number,
  language: Language,
  opponentHp: number | undefined,
): OpponentSpec {
  const profile = getAiProfile("normal");
  const { avatarFaceId, colors } = botAppearanceFromSeed("quick-opponent");
  const composite = createStickman(spawnX, spawnY, {
    scale: 1,
    render: { fillStyle: colors.main },
  });

  return {
    composite,
    headLabel: "Head",
    name: language === "ru" ? "БОТ-РЭГДОЛЛ" : "RAGDOLL BOT",
    maxHp: Math.max(1, Math.round(opponentHp ?? OPPONENT_MAX_HP)),
    colors,
    avatarFaceId,
    aiSpeedMult: profile.speedMult,
    aiProfile: profile,
    isMonster: false,
  };
}
