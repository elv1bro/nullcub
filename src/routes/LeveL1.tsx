import { HpOverlay } from "@/components/HpOverlay";
import { BattleTimer } from "@/components/BattleTimer";
import { BattleRecapOverlay } from "@/components/BattleRecapOverlay";
import { Viewport } from "@/components/Viewport";
import { unlockAfterWin } from "@/campaign/progress";
import { pickL10n } from "@/campaign/bouncer";
import { botEmotion } from "@/face/emotions";
import { useFaceTracker } from "@/face/tracker";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { setHeartbeatLevel } from "@/audio";
import { useGrabSystem } from "@/lib/grab";
import { tagStickmanHands } from "@/lib/grab/hands";
import type { GrabVisualLine } from "@/lib/grab/types";
import {
  getBattleConfig,
  setBattleResult,
} from "@/lib/battleConfig";
import { useImpactHandler } from "@/lib/handleImpacts";
import { PLAYER_MOVE_SPEED, battleSpawnPositions } from "@/lib/battleTuning";
import { capturePoseSnapshot } from "@/lib/ragdollPoseReset";
import type { PoseSnapshot } from "@/lib/ragdollPoseReset";
import { moveBody } from "@/lib/moveBody";
import { MAX_HP } from "@/lib/combat";
import { applyPlayerColors } from "@/lib/paintStickman";
import { resolveBattleOpponent } from "@/lib/resolveBattleOpponent";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";
import { useFighterMovement } from "@/battle/useFighterMovement";
import { useAIMoves } from "@/lib/useAIMoves";
import { usePlayerAbilities } from "@/lib/usePlayerAbilities";
import { useMonsterLinkPhysics } from "@/lib/useMonsterLinkPhysics";
import { useVictoryDefeatFx } from "@/lib/useVictoryDefeatFx";
import { useBattleRecapGate } from "@/lib/useBattleRecapGate";
import { e2eFail, e2eMatches, e2eOk, e2eSetPhase } from "@/dev/e2eHarness";
import { useBattleOverlay } from "@/lib/useBattleOverlay";
import { useBloodyParticules } from "@/lib/useBloodyParticules";
import { useHitEffectClock, createHitEffectStore } from "@/lib/hitEffects";
import { useHealth } from "@/lib/useHealth";
import {
  useBattleSession,
  useCoreGrabLines,
  useCoreInputBridge,
  type CoreFighterSpec,
} from "@/core";
import { createBattleMomentsStore } from "@/lib/battleMoments";
import {
  createBattleTracker,
  recordBattleEnd,
  type MedalId,
} from "@/lib/achievements";
import { useAchievements } from "@/achievements/AchievementsContext";
import { useNetSession } from "@/net/NetSessionContext";
import { useNetFaceSync } from "@/net/useNetFaceSync";
import { useNetRemoteFace } from "@/net/useNetRemoteFace";
import {
  useNetBattleBroadcast,
  useNetBattleHost,
  useNetInputReceiver,
  useNetRemoteGrabHeld,
  useNetRemoteOpponentMovement,
} from "@/net/useNetBattle";
import type { NetHitPayload } from "@/net/protocol";
import { createStickman } from "@/utils/createStickman";
import { Composite, SurroundingWalls } from "@1.framework/matter4react";
import debug from "debug";
import Matter, { Body, Vector, type IEventTimestamped } from "matter-js";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

export const log = debug("@:routes:LeveL1");

export const SIZE = 1000;

const ARENA_BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);

export function LeveL1() {
  log("!");
  const { profile, setLastBattleSnapshot } = usePlayerProfile();
  const { refreshStats } = useAchievements();
  const { t, settings } = useSettings();
  const battleConfig = useMemo(() => getBattleConfig(), []);
  const isLocal2P = battleConfig.kind === "local2p";
  const isNetHost = battleConfig.kind === "network";
  const coreSim = true;
  const net = useNetSession();
  const opponentSpec = useMemo(
    () => resolveBattleOpponent(battleConfig, SIZE, settings.language),
    [battleConfig, settings.language],
  );

  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const [impactComposites, setImpactComposites] = useState<Matter.Composite[]>(
    [],
  );
  const itemCompositesRef = useRef<Matter.Composite[]>([]);
  const [player, setPlayer] = useState<Matter.Composite>();
  const [opponent, setOpponent] = useState<Matter.Composite>();
  const [coreFighters, setCoreFighters] = useState<CoreFighterSpec[] | null>(
    null,
  );
  const playerAbilityFlags = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
  });
  const opponentAbilityFlags = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
  });
  const playerHead = useRef<Body>();
  const opponentHead = useRef<Body>();
  const playerCompositeRef = useRef<Matter.Composite>();
  const opponentCompositeRef = useRef<Matter.Composite>();
  const playerPoseSnapRef = useRef<PoseSnapshot | null>(null);
  const opponentPoseSnapRef = useRef<PoseSnapshot | null>(null);
  const battleOverRef = useRef(false);
  const battleStartRef = useRef(0);
  const aiSpeedMultRef = useRef(opponentSpec.aiSpeedMult);
  const botGrabLeftRef = useRef(false);
  const botGrabRightRef = useRef(false);
  const hitEffectsStoreRef = useRef(createHitEffectStore());
  const battleMomentsRef = useRef(createBattleMomentsStore());
  const battleTrackerRef = useRef(createBattleTracker());
  const [battleMedals, setBattleMedals] = useState<MedalId[]>([]);
  const [, setMomentsTick] = useState(0);
  const bumpMoments = useCallback(() => setMomentsTick((t) => t + 1), []);
  const campaignOutroRef = useRef<string | null>(null);
  const victoryHandledRef = useRef(false);

  aiSpeedMultRef.current = opponentSpec.aiSpeedMult;

  const healthFx = useMemo(
    () => ({
      formatDamage: t.hit.damage,
      showBanter: settings.showBanter,
      matureBanter: settings.matureBanter,
      screenEffects: settings.screenEffects,
      hitEffectsStore: hitEffectsStoreRef,
      arenaHeight: SIZE,
      language: settings.language,
      getKnockoutFocus: (winner: "player" | "opponent") => {
        const head = winner === "player" ? playerHead.current : opponentHead.current;
        return head
          ? { x: head.position.x, y: head.position.y - 20 }
          : null;
      },
      battleStartRef,
      battleMomentsStore: battleMomentsRef,
      battleTrackerRef,
      ourTeamName: profile.name,
      enemyTeamName: opponentSpec.name,
      opponentDefensePct: opponentSpec.defense ?? 0,
      getSpeakerHead: (side: "player" | "opponent") => {
        const head =
          side === "player" ? playerHead.current : opponentHead.current;
        return head
          ? { x: head.position.x, y: head.position.y - 22 }
          : null;
      },
      banterObstacleBodies: () => protagonists,
    }),
    [
      t,
      settings.showBanter,
      settings.matureBanter,
      settings.screenEffects,
      settings.language,
      profile.name,
      opponentSpec.name,
      opponentSpec.defense,
    ],
  );

  const allComposites = useMemo(
    () =>
      [...(player ? [player] : []), ...(opponent ? [opponent] : []), ...itemCompositesRef.current],
    [player?.id, opponent?.id, itemCompositesRef.current.length],
  );

  const grabSystem = useGrabSystem({
    fighterId: "player",
    playerCompositeRef: playerCompositeRef,
    allComposites,
    itemCompositesRef,
    disabledRef: battleOverRef,
    skipSimulation: coreSim,
  });

  const remoteInputRef = useNetInputReceiver(isNetHost);
  const remoteGrabLeftRef = useRef(false);
  const remoteGrabRightRef = useRef(false);
  useNetRemoteGrabHeld(
    remoteInputRef,
    remoteGrabLeftRef,
    remoteGrabRightRef,
    isNetHost,
  );

  const opponentGrabSystem = useGrabSystem({
    fighterId: "opponent",
    playerCompositeRef: opponentCompositeRef,
    allComposites,
    itemCompositesRef,
    disabledRef: battleOverRef,
    skipSimulation: coreSim,
    keyboardInput: isLocal2P,
    abilityBindings: isLocal2P ? settings.abilitiesP2 : undefined,
    externalHeldRefs: isNetHost
      ? {
          left: remoteGrabLeftRef,
          right: remoteGrabRightRef,
        }
      : opponentSpec.aiProfile
        ? {
            left: botGrabLeftRef,
            right: botGrabRightRef,
          }
        : undefined,
  });

  const mergedGrabLinesRef = useRef<GrabVisualLine[]>([]);
  useEffect(() => {
    if (!isNetHost) return;
    let raf = 0;
    const tick = () => {
      mergedGrabLinesRef.current = [
        ...grabSystem.linesRef.current,
        ...opponentGrabSystem.linesRef.current,
      ];
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [isNetHost, grabSystem.linesRef, opponentGrabSystem.linesRef]);

  const healthFxWithGrab = useMemo(
    () => ({
      ...healthFx,
      playerGrabRef: grabSystem.grabRef,
      opponentGrabRef: opponentGrabSystem.grabRef,
      releasePlayerGrab: grabSystem.releaseHand,
      releaseOpponentGrab: opponentGrabSystem.releaseHand,
      playerCompositeId: player?.id,
      opponentCompositeId: opponent?.id,
      itemCompositesRef,
      onItemDisarm: (composite: Matter.Composite) => {
        for (const body of composite.bodies) {
          Matter.Body.applyForce(body, body.position, {
            x: (Math.random() - 0.5) * 0.02,
            y: -0.015,
          });
        }
      },
    }),
    [
      healthFx,
      grabSystem.grabRef,
      opponentGrabSystem.grabRef,
      grabSystem.releaseHand,
      opponentGrabSystem.releaseHand,
      player?.id,
      opponent?.id,
    ],
  );

  const offlineFace = useFaceTracker({
    enabled: !isNetHost && profile.useCamera,
    audio: profile.useMicrophone,
    tracking: false,
  });
  const netFace = useNetFaceSync(
    profile.useCamera ? "video" : "none",
    isNetHost,
  );
  const remoteOpponentFace = useNetRemoteFace(isNetHost);
  const { ready, error, videoRef, cropRef } = isNetHost ? netFace : offlineFace;
  const health = useHealth(
    impactComposites,
    player?.id,
    opponent?.id,
    profile.colors,
    ARENA_BOUNDS,
    healthFxWithGrab,
    opponentSpec.maxHp,
    [
      player?.id,
      opponent?.id,
      opponentSpec.maxHp,
      profile.colors.main,
      profile.colors.secondary,
      settings.showBanter,
      settings.matureBanter,
      settings.screenEffects,
      settings.language,
    ],
    coreSim ? { skipCollisions: true } : undefined,
  );

  const coreSessionViewRef = useRef<ReturnType<typeof useBattleSession> | null>(
    null,
  );
  /** Стабильный box на sessionRef — bridge регистрируется до session.tick. */
  const sessionRefBox = useRef<
    import("react").MutableRefObject<import("@/core").BattleSession | null> | null
  >(null);

  useCoreInputBridge({
    enabled: coreSim && Boolean(coreFighters?.length),
    setPlayerInput: (input) => {
      sessionRefBox.current?.current?.setInput("player", input);
    },
    setOpponentInput: (input) => {
      sessionRefBox.current?.current?.setInput("opponent", input);
    },
    playerControls: settings.controls,
    opponentControls: settings.controlsP2,
    playerGrabL: grabSystem.leftHeldRef,
    playerGrabR: grabSystem.rightHeldRef,
    opponentGrabL: opponentGrabSystem.leftHeldRef,
    opponentGrabR: opponentGrabSystem.rightHeldRef,
    playerAbilityFlags,
    opponentAbilityFlags,
    remoteOpponentInput: isNetHost ? remoteInputRef : undefined,
    includeOpponentLocal: isLocal2P,
  });

  const coreSession = useBattleSession({
    enabled: coreSim && Boolean(coreFighters?.length),
    arenaSize: SIZE,
    fighters: coreFighters,
    playerCompositeId: player?.id,
    opponentCompositeId: opponent?.id,
    itemComposites: itemCompositesRef.current,
    battleStartMs: battleStartRef.current,
    externalRunner: true,
    onHit: (payload) => {
      const session = coreSessionViewRef.current?.sessionRef.current;
      if (!session) return;
      const victimSide =
        payload.victimCompositeId === player?.id
          ? ("player" as const)
          : payload.victimCompositeId === opponent?.id
            ? ("opponent" as const)
            : null;
      health.syncHpFromCore(
        session.getHp("player"),
        session.getHp("opponent"),
        victimSide,
      );
      health.reportCoreHit(payload);
    },
    onKnockout: (payload) => {
      const head =
        payload.victimCompositeId === player?.id
          ? playerHead.current
          : opponentHead.current;
      health.reportCoreKnockout(
        payload,
        head?.position.x ?? SIZE / 2,
        head?.position.y ?? SIZE / 2,
      );
    },
    onDisarm: (_fighterId, item) => {
      for (const body of item.bodies) {
        Matter.Body.applyForce(body, body.position, {
          x: (Math.random() - 0.5) * 0.02,
          y: -0.015,
        });
      }
    },
  });
  coreSessionViewRef.current = coreSession;
  sessionRefBox.current = coreSession.sessionRef;

  const playerHp = coreSim && coreFighters ? coreSession.playerHp : health.playerHp;
  const opponentHp =
    coreSim && coreFighters ? coreSession.opponentHp : health.opponentHp;
  const battleOver =
    coreSim && coreFighters ? coreSession.battleOver : health.battleOver;
  const winner =
    coreSim && coreFighters
      ? (coreSession.winner as "player" | "opponent" | null)
      : health.winner;
  const lastHit = health.lastHit;

  battleOverRef.current = battleOver;
  const showRecap = useBattleRecapGate(battleOver);

  useEffect(() => {
    if (!e2eMatches("quick")) return;
    e2eSetPhase("running");
    if (battleOver) {
      e2eFail("quick battle ended early");
      return;
    }
    const t = setTimeout(() => {
      if (playerHp > 0 && opponentHp > 0 && !battleOver) {
        e2eOk({ playerHp, opponentHp, mode: "quick" });
      } else {
        e2eFail(`quick battle hp: ${playerHp}/${opponentHp}`);
      }
    }, 5000);
    return () => clearTimeout(t);
  }, [playerHp, opponentHp, battleOver]);

  const guestName = net.peers[0]?.name ?? opponentSpec.name;
  const hostName = profile.name;

  const battleStatePayload = useMemo(
    () => ({
      playerHp,
      opponentHp,
      battleOver,
      winner,
      playerName: hostName,
      opponentName: guestName,
    }),
    [playerHp, opponentHp, battleOver, winner, hostName, guestName],
  );
  useNetBattleBroadcast(isNetHost, battleStatePayload);
  useNetBattleHost(allComposites, isNetHost);

  const prevHpRef = useRef({
    player: playerHp,
    opponent: opponentHp,
  });
  useEffect(() => {
    if (!isNetHost || !net.actions) return;
    const [sendHit] = net.actions.hit;
    const prev = prevHpRef.current;
    const playerDamage = prev.player - playerHp;
    const opponentDamage = prev.opponent - opponentHp;
    if (playerDamage > 0.5 && lastHit === "player") {
      const head = playerHead.current;
      const payload: NetHitPayload = {
        victimId: "player",
        damage: playerDamage,
        damageType: "blunt",
        x: head?.position.x ?? 0,
        y: head?.position.y ?? 0,
      };
      sendHit(payload, []);
    }
    if (opponentDamage > 0.5 && lastHit === "opponent") {
      const head = opponentHead.current;
      const payload: NetHitPayload = {
        victimId: "opponent",
        damage: opponentDamage,
        damageType: "blunt",
        x: head?.position.x ?? 0,
        y: head?.position.y ?? 0,
      };
      sendHit(payload, []);
    }
    prevHpRef.current = {
      player: playerHp,
      opponent: opponentHp,
    };
  }, [
    isNetHost,
    net.actions,
    playerHp,
    opponentHp,
    lastHit,
  ]);

  const webcamActive = profile.useCamera && ready && !error;

  // Сердцебиение при HP < 30%: чем ближе к нулю, тем чаще и громче.
  useEffect(() => {
    if (battleOver) {
      setHeartbeatLevel(0);
      return;
    }
    const ratio = playerHp / MAX_HP;
    setHeartbeatLevel(ratio < 0.3 ? (0.3 - ratio) / 0.3 : 0);
  }, [playerHp, battleOver]);

  useEffect(() => () => setHeartbeatLevel(0), []);

  useEffect(() => {
    battleTrackerRef.current = createBattleTracker();
    battleMomentsRef.current = createBattleMomentsStore();
    setBattleMedals([]);
    victoryHandledRef.current = false;
    campaignOutroRef.current = null;
  }, [player?.id, opponent?.id]);

  useEffect(() => {
    if (!battleOver || victoryHandledRef.current) return;
    victoryHandledRef.current = true;

    // winner === null при battleOver — двойной нокаут (ничья).
    const outcome = winner ?? "draw";
    const config = getBattleConfig();
    const { medals } = recordBattleEnd({
      tracker: battleTrackerRef.current,
      winner: outcome,
      playerHp,
      battleConfig: config,
    });
    setBattleMedals(medals);
    refreshStats();
    setLastBattleSnapshot({
      avatarFaceId: profile.useCamera ? null : profile.avatarFaceId,
      medalId: medals[0] ?? null,
    });

    setBattleResult({ winner: outcome, config });

    if (
      winner === "player" &&
      config.kind === "campaign" &&
      opponentSpec.campaignChapter
    ) {
      unlockAfterWin(opponentSpec.campaignChapter.id);
      campaignOutroRef.current = pickL10n(
        opponentSpec.campaignChapter.outro,
        settings.language,
      );
    }
  }, [
    battleOver,
    winner,
    playerHp,
    opponentSpec.campaignChapter,
    profile.useCamera,
    profile.avatarFaceId,
    refreshStats,
    setLastBattleSnapshot,
    settings.language,
  ]);

  const [painSide, setPainSide] = useState<"player" | "opponent" | null>(null);
  useEffect(() => {
    if (!lastHit) return;
    setPainSide(lastHit);
    const timer = setTimeout(() => setPainSide(null), 450);
    return () => clearTimeout(timer);
  }, [lastHit, playerHp, opponentHp]);

  const opponentFace = botEmotion(
    opponentHp,
    opponentSpec.maxHp,
    painSide === "opponent",
  );

  const opponentFaceForOverlay =
    opponentSpec.avatarFaceId || isNetHost
      ? isNetHost
        ? remoteOpponentFace.webcamActive
          ? null
          : remoteOpponentFace.face
        : null
      : opponentFace;

  const playerHud = useMemo(
    () => ({
      name: profile.name,
      hearts: playerHp,
      colors: profile.colors,
      side: "left" as const,
    }),
    [playerHp, profile.name, profile.colors],
  );

  const opponentHud = useMemo(
    () => ({
      name: guestName,
      hearts: opponentHp,
      colors: opponentSpec.colors,
      side: "right" as const,
    }),
    [opponentHp, guestName, opponentSpec.colors],
  );

  useEffect(() => {
    victoryHandledRef.current = false;
    campaignOutroRef.current = null;

    const { playerX, y: spawnY } = battleSpawnPositions(SIZE);
    const stickman_left = createStickman(playerX, spawnY, {
      render: { fillStyle: profile.colors.main },
    });
    applyPlayerColors(
      stickman_left,
      profile.colors.main,
      profile.colors.secondary,
    );

    const stickman_right = opponentSpec.composite;
    if (!opponentSpec.isMonster) {
      applyPlayerColors(
        stickman_right,
        opponentSpec.colors.main,
        opponentSpec.colors.secondary,
      );
    }

    const head = stickman_left.bodies.find((b) => b.label === "Head");
    const botHead = stickman_right.bodies.find((b) => b.label === "Head");
    if (head) head.render.visible = false;
    if (botHead) botHead.render.visible = false;

    tagStickmanHands(stickman_left, "player");
    tagStickmanHands(stickman_right, "opponent");

    for (const body of [...stickman_left.bodies, ...stickman_right.bodies]) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }

    setPlayer(stickman_left);
    setOpponent(stickman_right);
    playerCompositeRef.current = stickman_left;
    opponentCompositeRef.current = stickman_right;
    playerPoseSnapRef.current = capturePoseSnapshot(stickman_left);
    opponentPoseSnapRef.current = capturePoseSnapshot(stickman_right);
    playerHead.current = head;
    opponentHead.current = botHead;
    setProtagonists([...stickman_right.bodies, ...stickman_left.bodies]);
    // Предметы спавним и в монстро-боях — оружие должно иметь значение везде.
    const spawnedItems = spawnArenaItems(DEFAULT_ARENA_ITEMS, [
      ...ARENA_ITEM_SPAWN_POSITIONS,
    ]);
    itemCompositesRef.current = spawnedItems;
    setImpactComposites([stickman_left, stickman_right, ...spawnedItems]);
    battleStartRef.current = performance.now();
    setCoreFighters([
      {
        id: "player",
        composite: stickman_left,
        head: head!,
        maxHp: MAX_HP,
        // Бот бьёт игрока сильнее (×BOT_DAMAGE_MULTIPLIER); в локальном 2P буста нет.
        isBotDamageTarget: !isLocal2P,
      },
      {
        id: "opponent",
        composite: stickman_right,
        head: botHead!,
        maxHp: opponentSpec.maxHp,
        aiProfile: isLocal2P ? null : opponentSpec.aiProfile,
        defensePct: opponentSpec.defense,
      },
    ]);
    battleMomentsRef.current = createBattleMomentsStore();
    setMomentsTick((t) => t + 1);
  }, [
    profile.colors.main,
    profile.colors.secondary,
    opponentSpec.composite.id,
    opponentSpec.isMonster,
    opponentSpec.colors.main,
    opponentSpec.colors.secondary,
    battleConfig.kind,
    opponentSpec.maxHp,
    opponentSpec.aiProfile,
    opponentSpec.defense,
    isLocal2P,
  ]);

  useMonsterLinkPhysics(player, Boolean(player));
  useMonsterLinkPhysics(opponent, Boolean(opponent));

  const abilities = usePlayerAbilities(
    playerHead,
    playerCompositeRef,
    playerPoseSnapRef,
    battleOverRef,
    coreSim
      ? {
          skipPhysics: true,
          abilityFlagsOut: playerAbilityFlags,
        }
      : undefined,
  );

  const opponentAbilities = usePlayerAbilities(
    opponentHead,
    opponentCompositeRef,
    opponentPoseSnapRef,
    battleOverRef,
    {
      enabled: isLocal2P,
      abilities: settings.abilitiesP2,
      controls: settings.controlsP2,
      ...(coreSim
        ? {
            skipPhysics: true,
            abilityFlagsOut: opponentAbilityFlags,
          }
        : {}),
    },
  );

  useCoreGrabLines(
    coreSession.sessionRef,
    playerCompositeRef,
    "player",
    grabSystem.linesRef,
    coreSim,
  );
  useCoreGrabLines(
    coreSession.sessionRef,
    opponentCompositeRef,
    "opponent",
    opponentGrabSystem.linesRef,
    coreSim,
  );

  const combatFx = useMemo(
    () => ({
      playerCompositeId: player?.id,
      opponentCompositeId: opponent?.id,
      playerColors: profile.colors,
      opponentColors: opponentSpec.colors,
    }),
    [player?.id, opponent?.id, profile.colors, opponentSpec.colors],
  );

  useImpactHandler(
    impactComposites,
    combatFx,
    [player?.id, opponent?.id, profile.colors, opponentSpec.colors.main],
    battleStartRef,
    battleOverRef,
    abilities.braceActiveRef,
    !coreSim,
  );
  useBloodyParticules(
    impactComposites,
    combatFx,
    [player?.id, opponent?.id, profile.colors],
    battleOverRef,
  );
  const aiDisabledRef = useRef(false);
  aiDisabledRef.current = battleOver || isLocal2P || isNetHost || coreSim;

  useNetRemoteOpponentMovement(
    opponentHead,
    remoteInputRef,
    battleOverRef,
    undefined,
    isNetHost && !coreSim,
  );

  useFighterMovement(
    playerHead,
    isLocal2P || coreSim ? "none" : "keyboard",
    battleOverRef,
    abilities.moveSpeedMultRef,
    abilities.inputBlockedRef,
  );
  useFighterMovement(
    opponentHead,
    isLocal2P || coreSim ? "none" : "keyboard2",
    battleOverRef,
    isLocal2P ? opponentAbilities.moveSpeedMultRef : undefined,
    isLocal2P ? opponentAbilities.inputBlockedRef : undefined,
  );
  useAIMoves(
    opponentHead,
    playerHead,
    aiDisabledRef,
    ARENA_BOUNDS,
    aiSpeedMultRef,
    opponentSpec.aiProfile,
    botGrabLeftRef,
    botGrabRightRef,
    opponentCompositeRef,
  );
  useVictoryDefeatFx({
    battleOver,
    winner,
    screenEffects: settings.screenEffects,
    playerCompositeRef,
    opponentCompositeRef,
    hitEffectsStore: hitEffectsStoreRef,
    playerColors: profile.colors,
    opponentColors: opponentSpec.colors,
  });
  useHitEffectClock(hitEffectsStoreRef);
  useBattleOverlay(
    {
      playerHead,
      opponentHead,
      playerComposite: player,
      opponentComposite: opponent,
      playerVideo: videoRef,
      playerCrop: cropRef,
      opponentFace: opponentFaceForOverlay,
      opponentAvatarFaceId: opponentSpec.avatarFaceId,
      opponentHp,
      opponentMaxHp: opponentSpec.maxHp,
      opponentPain: painSide === "opponent",
      opponentLastHit: lastHit,
      opponentVideo: remoteOpponentFace.videoRef,
      opponentCrop: remoteOpponentFace.cropRef,
      opponentWebcamActive: remoteOpponentFace.webcamActive,
      playerPain: painSide === "player",
      webcamActive,
      faceEffect: profile.faceEffect,
      avatarFaceId: webcamActive ? undefined : profile.avatarFaceId,
      playerHp,
      playerMaxHp: MAX_HP,
      playerLastHit: lastHit,
      playerHud,
      opponentHud,
      popupsRef: health.popupsRef,
      burstsRef: health.burstsRef,
      banterRef: health.banterRef,
      hitEffectsStore: hitEffectsStoreRef,
      language: settings.language,
      lastHitDebug: health.lastHitDebugRef,
      battleMomentsStore: battleMomentsRef,
      onMomentCaptured: bumpMoments,
      grabLinesRef: isNetHost ? mergedGrabLinesRef : grabSystem.linesRef,
    },
    [
      opponentFaceForOverlay,
      opponentSpec.avatarFaceId,
      opponentHp,
      opponentSpec.maxHp,
      lastHit,
      remoteOpponentFace.webcamActive,
      remoteOpponentFace.face,
      painSide,
      playerHud,
      opponentHud,
      webcamActive,
      profile.faceEffect,
      profile.avatarFaceId,
      playerHp,
      lastHit,
      player,
      opponent,
      settings.language,
      settings.screenEffects,
    ],
  );

  const campaignOutro =
    battleOver &&
    winner === "player" &&
    battleConfig.kind === "campaign"
      ? campaignOutroRef.current ??
        (opponentSpec.campaignChapter
          ? pickL10n(opponentSpec.campaignChapter.outro, settings.language)
          : null)
      : null;

  return (
    <>
      <video
        ref={videoRef}
        className="fixed bottom-4 right-4 w-24 h-18 object-cover rounded border border-gray-700 opacity-50 z-20 mirror"
        muted
        playsInline
        aria-hidden
      />
      <HpOverlay
        battleOver={battleOver}
        showRecap={showRecap}
        winner={winner}
        faceReady={ready}
        faceError={error}
        abilities={abilities}
        local2p={isLocal2P}
        opponentAbilities={isLocal2P ? opponentAbilities : undefined}
        controlsP2={settings.controlsP2}
      />
      <BattleTimer
        startRef={battleStartRef}
        battleOver={battleOver}
        showRecap={showRecap}
      />
      <BattleRecapOverlay
        battleOver={battleOver}
        showRecap={showRecap}
        winner={winner}
        ourTeamName={profile.name}
        enemyTeamName={opponentSpec.name}
        moments={battleMomentsRef.current}
        campaignOutro={campaignOutro}
        battleMedals={battleMedals}
      />
      <Viewport protagonists={protagonists} hitEffectsStore={hitEffectsStoreRef} />
      <SurroundingWalls
        thick={SIZE}
        bounds={ARENA_BOUNDS}
        options={{ render: { fillStyle: "#333" } }}
      />
      {player && <Composite.add object={player} />}
      {opponent && <Composite.add object={opponent} />}
      {itemCompositesRef.current.map((item) => (
        <Composite.add key={item.id} object={item} />
      ))}
    </>
  );
}
