import { HpOverlay } from "@/components/HpOverlay";
import {
  BattleOnboarding,
  hasSeenBattleOnboarding,
  markBattleOnboardingSeen,
} from "@/components/BattleOnboarding";
import { BattleTimer } from "@/components/BattleTimer";
import { BattleRecapOverlay } from "@/components/BattleRecapOverlay";
import { FightReplayHud } from "@/components/FightReplayHud";
import {
  VirtualBattleStick,
  type TouchMoveVec,
} from "@/components/VirtualBattleStick";
import { BattleSpaceBg } from "@/components/BattleSpaceBg";
import { Viewport } from "@/components/Viewport";
import {
  battleBackdropLabel,
  pickBattleBackdrop,
  type BattleBackdropId,
} from "@/render/battleBackdrops";
import { unlockAfterWin } from "@/campaign/progress";
import { pickL10n } from "@/campaign/bouncer";
import { botEmotion } from "@/face/emotions";
import { useFaceTracker } from "@/face/tracker";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { playBattleMusic, setHeartbeatLevel } from "@/audio";
import { FullscreenToggle } from "@/components/FullscreenToggle";
import { useGrabSystem } from "@/lib/grab";
import { tagStickmanHands } from "@/lib/grab/hands";
import type { GrabVisualLine } from "@/lib/grab/types";
import {
  getBattleConfig,
  setBattleResult,
} from "@/lib/battleConfig";
import { useImpactHandler } from "@/lib/handleImpacts";
import {
  BATTLE_TIME_LIMIT_MS,
  battleSpawnPositions,
} from "@/lib/battleTuning";
import { capturePoseSnapshot } from "@/lib/ragdollPoseReset";
import type { PoseSnapshot } from "@/lib/ragdollPoseReset";
import { MAX_HP } from "@/lib/combat";
import { OPPONENT_COLORS } from "@/lib/fighterColors";
import { applyPlayerColors } from "@/lib/paintStickman";
import { resolveBattleOpponent } from "@/lib/resolveBattleOpponent";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";
import { useFighterMovement } from "@/battle/useFighterMovement";
import { useAIMoves } from "@/lib/useAIMoves";
import { usePlayerAbilities } from "@/lib/usePlayerAbilities";
import { useMonsterLinkPhysics } from "@/lib/useMonsterLinkPhysics";
import { useVictoryDefeatFx } from "@/lib/useVictoryDefeatFx";
import { useBattleEndPhases } from "@/lib/useBattleRecapGate";
import { FightTape } from "@/lib/fightTape";
import { useFightReplay } from "@/lib/useFightReplay";
import {
  e2eFail,
  e2eMatches,
  e2eOk,
  e2eSetPhase,
  getE2EScenario,
} from "@/dev/e2eHarness";
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
import {
  Composite,
  SurroundingWalls,
  useEventBeforeUpdate,
} from "@1.framework/matter4react";
import debug from "debug";
import Matter, { Body } from "matter-js";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

export const log = debug("@:routes:LeveL1");

export const SIZE = 1000;

/** E2E: не перезапускать battle-assert при remount LeveL1. */
let e2eBattleArmed = false;

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
  const isLabLike =
    battleConfig.kind === "lab" || battleConfig.kind === "testArena";
  const playerMaxHp =
    battleConfig.kind === "testArena" ? battleConfig.playerHp : MAX_HP;
  const coreSim = true;
  const net = useNetSession();
  const opponentSpec = useMemo(
    () => resolveBattleOpponent(battleConfig, SIZE, settings.language),
    [battleConfig, settings.language],
  );
  const opponentMaxHp =
    battleConfig.kind === "testArena"
      ? battleConfig.opponentHp
      : opponentSpec.maxHp;

  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const [impactComposites, setImpactComposites] = useState<Matter.Composite[]>(
    [],
  );
  const itemCompositesRef = useRef<Matter.Composite[]>([]);
  const [player, setPlayer] = useState<Matter.Composite>();
  const [opponent, setOpponent] = useState<Matter.Composite>();
  const [extraBots, setExtraBots] = useState<
    Array<{
      id: string;
      composite: Matter.Composite;
      head: Body;
      maxHp: number;
      name: string;
    }>
  >([]);
  const [coreFighters, setCoreFighters] = useState<CoreFighterSpec[] | null>(
    null,
  );
  const playerAbilityFlags = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
    dropWeapon: false,
    abilitySlot: false,
  });
  const opponentAbilityFlags = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
    dropWeapon: false,
    abilitySlot: false,
  });
  const touchMoveRef = useRef<TouchMoveVec>({ x: 0, y: 0 });
  const [backdropId, setBackdropId] = useState<BattleBackdropId>(() =>
    pickBattleBackdrop(),
  );
  const playerHead = useRef<Body>();
  const opponentHead = useRef<Body>();
  const playerCompositeRef = useRef<Matter.Composite>();
  const opponentCompositeRef = useRef<Matter.Composite>();
  const playerPoseSnapRef = useRef<PoseSnapshot | null>(null);
  const opponentPoseSnapRef = useRef<PoseSnapshot | null>(null);
  const battleOverRef = useRef(false);
  const bloodySpawnRef = useRef<
    (
      x: number,
      y: number,
      color: string,
      damageHint?: number,
      dir?: { x: number; y: number },
    ) => void
  >(() => undefined);
  const bloodyClearRef = useRef<() => void>(() => undefined);
  const replayClipEndMsRef = useRef<number | null>(null);
  const battleStartRef = useRef(0);
  const aiSpeedMultRef = useRef(opponentSpec.aiSpeedMult);
  const botGrabLeftRef = useRef(false);
  const botGrabRightRef = useRef(false);
  const hitEffectsStoreRef = useRef(createHitEffectStore());
  const battleMomentsRef = useRef(createBattleMomentsStore());
  const fightTapeRef = useRef(new FightTape());
  const battleTrackerRef = useRef(createBattleTracker());
  const [battleMedals, setBattleMedals] = useState<MedalId[]>([]);
  const [showBattleOnboard, setShowBattleOnboard] = useState(() => {
    if (typeof window !== "undefined" && getE2EScenario()) return false;
    return !hasSeenBattleOnboarding();
  });
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
    () => [
      ...(player ? [player] : []),
      ...(opponent ? [opponent] : []),
      ...extraBots.map((b) => b.composite),
      ...itemCompositesRef.current,
    ],
    [
      player?.id,
      opponent?.id,
      extraBots,
      itemCompositesRef.current.length,
    ],
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
    opponentMaxHp,
    [
      player?.id,
      opponent?.id,
      opponentMaxHp,
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
    setInput: (fighterId, input) => {
      sessionRefBox.current?.current?.setInput(fighterId, input);
    },
    slots:
      coreSim && isLocal2P
        ? [
            {
              fighterId: "player",
              controls: settings.controls,
              grabL: grabSystem.leftHeldRef,
              grabR: grabSystem.rightHeldRef,
              abilityFlags: playerAbilityFlags,
              gamepadIndex: 0,
              externalMoveRef: touchMoveRef,
            },
            {
              fighterId: "opponent",
              controls: settings.controlsP2,
              grabL: opponentGrabSystem.leftHeldRef,
              grabR: opponentGrabSystem.rightHeldRef,
              abilityFlags: opponentAbilityFlags,
              gamepadIndex: 1,
            },
          ]
        : undefined,
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
    playerExternalMoveRef: touchMoveRef,
    playerGamepadIndex: 0,
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
      const pHp = session.getHp("player");
      const oHp = session.getHp("opponent");
      if (victimSide) {
        const victimHead =
          victimSide === "player" ? playerHead.current : opponentHead.current;
        const aggressorHead =
          victimSide === "player" ? opponentHead.current : playerHead.current;
        const dirX =
          (victimHead?.position.x ?? payload.x) -
          (aggressorHead?.position.x ?? payload.x);
        const dirY =
          (victimHead?.position.y ?? payload.y) -
          (aggressorHead?.position.y ?? payload.y);
        fightTapeRef.current.noteHit(payload.damage, {
          x: payload.x,
          y: payload.y,
          victimSide,
          damageTypeId: payload.damageTypeId,
          dirX,
          dirY,
          playerHp: pHp,
          opponentHp: oHp,
        });
        const combo = hitEffectsStoreRef.current?.combo?.count ?? 0;
        if (combo > 0) fightTapeRef.current.noteCombo(combo);
      } else {
        fightTapeRef.current.noteHp(pHp, oHp);
        fightTapeRef.current.noteHit(payload.damage);
      }
    },
    onKnockout: (payload) => {
      const head =
        payload.victimCompositeId === player?.id
          ? playerHead.current
          : opponentHead.current;
      const kx = head?.position.x ?? SIZE / 2;
      const ky = head?.position.y ?? SIZE / 2;
      health.reportCoreKnockout(payload, kx, ky);
      const victimSide =
        payload.victimCompositeId === player?.id
          ? ("player" as const)
          : payload.victimCompositeId === opponent?.id
            ? ("opponent" as const)
            : null;
      const session = coreSessionViewRef.current?.sessionRef.current;
      const pHp = session?.getHp("player") ?? 0;
      const oHp = session?.getHp("opponent") ?? 0;
      if (victimSide) {
        fightTapeRef.current.noteKo({
          x: kx,
          y: ky,
          victimSide,
          playerHp: pHp,
          opponentHp: oHp,
        });
      } else {
        fightTapeRef.current.noteKo();
      }
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
  const playerHpRef = useRef(playerHp);
  const opponentHpRef = useRef(opponentHp);
  playerHpRef.current = playerHp;
  opponentHpRef.current = opponentHp;
  const rawWinner =
    coreSim && coreFighters ? coreSession.winner : health.winner;
  const winner = useMemo((): "player" | "opponent" | null => {
    if (!rawWinner) return null;
    if (rawWinner === "player" || rawWinner === "opponent") return rawWinner;
    const f = coreSession.sessionRef.current?.getFighter(rawWinner);
    if (f?.team === 0) return "player";
    if (f?.team === 1) return "opponent";
    return "opponent";
  }, [rawWinner, battleOver, coreSession.sessionRef]);
  const lastHit = health.lastHit;

  battleOverRef.current = battleOver;

  const getReplayBodies = useCallback((): Body[] => {
    const list: Body[] = [];
    if (playerCompositeRef.current) list.push(...playerCompositeRef.current.bodies);
    if (opponentCompositeRef.current) {
      list.push(...opponentCompositeRef.current.bodies);
    }
    for (const bot of extraBots) list.push(...bot.composite.bodies);
    for (const item of itemCompositesRef.current) list.push(...item.bodies);
    return list;
  }, [extraBots]);

  // При KO кадры уже в ленте — battleOver-рендер сразу видит frameCount.
  const hasReplayTape = battleOver && fightTapeRef.current.frameCount > 2;
  const { showReplay, showRecap, goToRecap } = useBattleEndPhases(
    battleOver,
    hasReplayTape,
  );

  useEffect(() => {
    // Replay идёт ещё в XState "battle" — добиваем музыку, если её уже успели срубить.
    if (showReplay) playBattleMusic();
  }, [showReplay]);

  const onReplayEvent = useCallback(
    (event: {
      kind: "hit" | "ko";
      damage: number;
      x: number;
      y: number;
      victimSide: "player" | "opponent";
      damageTypeId?: string;
      dirX?: number;
      dirY?: number;
    }) => {
      health.replayVisualHit({
        victimSide: event.victimSide,
        damage: event.damage,
        x: event.x,
        y: event.y,
        damageTypeId: event.damageTypeId,
        knockout: event.kind === "ko",
      });
      // Кругляши-обломки: live-коллизии в replay выключены (battleOver + timeScale=0).
      if (event.damage > 0.5 || event.kind === "ko") {
        const color =
          event.victimSide === "player"
            ? profile.colors.main
            : opponentSpec.colors.main;
        const dir =
          event.dirX != null && event.dirY != null
            ? { x: event.dirX, y: event.dirY }
            : undefined;
        bloodySpawnRef.current(
          event.x,
          event.y,
          color,
          event.kind === "ko" ? Math.max(event.damage, 40) : event.damage,
          dir,
        );
      }
    },
    [health, opponentSpec.colors.main, profile.colors.main],
  );

  const clearReplayFx = useCallback(() => {
    health.clearReplayFx();
    bloodyClearRef.current();
  }, [health]);

  const replay = useFightReplay({
    enabled: showReplay,
    tapeRef: fightTapeRef,
    getBodies: getReplayBodies,
    onReplayEvent,
    onClearReplayFx: clearReplayFx,
    onEnded: goToRecap,
    initialMode: "auto",
    clipEndMsRef: replayClipEndMsRef,
  });

  const [, setSuddenTick] = useState(0);
  useEffect(() => {
    if (showReplay || showRecap || battleOver) return;
    if (!battleStartRef.current) return;
    const id = window.setInterval(() => setSuddenTick((n) => n + 1), 400);
    return () => window.clearInterval(id);
  }, [showReplay, showRecap, battleOver, battleStartRef.current]);
  const battleElapsedMs = battleStartRef.current
    ? Math.max(0, performance.now() - battleStartRef.current)
    : 0;
  const suddenDeathLive =
    !showReplay &&
    !showRecap &&
    battleStartRef.current > 0 &&
    battleElapsedMs >= BATTLE_TIME_LIMIT_MS;
  const suddenDeathReplay =
    showReplay && replay.playheadMs >= BATTLE_TIME_LIMIT_MS;
  const suddenDeathActive = suddenDeathLive || suddenDeathReplay;

  useEventBeforeUpdate(() => {
    if (showReplay || showRecap) return;
    if (!battleStartRef.current) return;
    const tape = fightTapeRef.current;
    if (tape.isFrozen) return;
    const session = sessionRefBox.current?.current;
    const hp = {
      player:
        session?.getHp("player") ??
        (battleOverRef.current ? playerHp : playerMaxHp),
      opponent:
        session?.getHp("opponent") ??
        (battleOverRef.current ? opponentHp : opponentMaxHp),
    };
    // Бой идёт, или после KO ещё пишем ~5с разлёта.
    if (!battleOverRef.current || tape.wantsPostKoTail()) {
      tape.maybeSample(performance.now(), getReplayBodies(), hp);
      return;
    }
    tape.maybeSample(performance.now(), getReplayBodies(), hp);
    tape.freeze();
  }, [
    getReplayBodies,
    showReplay,
    showRecap,
    opponentMaxHp,
    playerMaxHp,
    playerHp,
    opponentHp,
  ]);

  // Одноразовый e2e-таймер (module-level): remount / HP-updates не сбрасывают.
  useEffect(() => {
    if (!e2eMatches("quick") && !e2eMatches("workshopFight")) return;
    e2eSetPhase("running");
    if (e2eBattleArmed) return;
    e2eBattleArmed = true;
    const kind = battleConfig.kind;
    window.setTimeout(() => {
      const pHp = playerHpRef.current;
      const oHp = opponentHpRef.current;
      if (pHp > 0 && oHp > 0 && !battleOverRef.current) {
        e2eOk({
          playerHp: pHp,
          opponentHp: oHp,
          mode: e2eMatches("workshopFight") ? "workshopFight" : "quick",
          monster: kind === "monster",
        });
      } else {
        e2eFail(`battle hp: ${pHp}/${oHp}`);
      }
    }, e2eMatches("workshopFight") ? 3500 : 5000);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- e2e once per page
  }, []);

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
    const ratio = playerHp / playerMaxHp;
    setHeartbeatLevel(ratio < 0.3 ? (0.3 - ratio) / 0.3 : 0);
  }, [playerHp, battleOver]);

  useEffect(() => () => setHeartbeatLevel(0), []);

  useEffect(() => {
    battleTrackerRef.current = createBattleTracker();
    battleMomentsRef.current = createBattleMomentsStore();
    fightTapeRef.current.clear();
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
    opponentMaxHp,
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

  const replayHp = showReplay
    ? fightTapeRef.current.hpAt(replay.playheadMs)
    : null;
  const viewPlayerHp = replayHp?.playerHp ?? playerHp;
  const viewOpponentHp = replayHp?.opponentHp ?? opponentHp;

  const playerHud = useMemo(
    () => ({
      name: profile.name,
      hearts: viewPlayerHp,
      maxHearts: playerMaxHp,
      colors: profile.colors,
      side: "left" as const,
    }),
    [viewPlayerHp, profile.name, profile.colors, playerMaxHp],
  );

  const opponentHud = useMemo(
    () => ({
      name: guestName,
      hearts: viewOpponentHp,
      maxHearts: opponentMaxHp,
      colors: opponentSpec.colors,
      side: "right" as const,
    }),
    [viewOpponentHp, guestName, opponentSpec.colors, opponentMaxHp],
  );

  const playerStatus = useMemo(
    () => ({
      name: profile.name,
      hp: viewPlayerHp,
      maxHp: playerMaxHp,
      color: profile.colors.main,
      secondaryColor: profile.colors.secondary,
    }),
    [
      viewPlayerHp,
      profile.name,
      profile.colors.main,
      profile.colors.secondary,
      playerMaxHp,
    ],
  );

  const opponentStatus = useMemo(
    () => ({
      name: guestName,
      hp: viewOpponentHp,
      maxHp: opponentMaxHp,
      color: opponentSpec.colors.main,
      secondaryColor: opponentSpec.colors.secondary,
    }),
    [
      viewOpponentHp,
      guestName,
      opponentMaxHp,
      opponentSpec.colors.main,
      opponentSpec.colors.secondary,
    ],
  );

  useEffect(() => {
    victoryHandledRef.current = false;
    campaignOutroRef.current = null;

    const { playerX, opponentX, y: spawnY } = battleSpawnPositions(SIZE);
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

    const botCount =
      battleConfig.kind === "testArena" ? battleConfig.opponentCount : 1;
    const spawnedExtras: Array<{
      id: string;
      composite: Matter.Composite;
      head: Body;
      maxHp: number;
      name: string;
    }> = [];
    for (let i = 1; i < botCount; i++) {
      const id = `bot${i + 1}`;
      const x = Math.min(SIZE - 70, opponentX + 70 * i);
      const y = spawnY + (i % 2 === 0 ? -70 : 70) * Math.ceil(i / 2);
      const composite = createStickman(x, y, {
        render: { fillStyle: OPPONENT_COLORS.main },
      });
      applyPlayerColors(
        composite,
        OPPONENT_COLORS.main,
        OPPONENT_COLORS.secondary,
      );
      const eHead = composite.bodies.find((b) => b.label === "Head");
      if (eHead) eHead.render.visible = false;
      tagStickmanHands(composite, id);
      for (const body of composite.bodies) {
        Body.setVelocity(body, { x: 0, y: 0 });
        Body.setAngularVelocity(body, 0);
      }
      if (eHead) {
        spawnedExtras.push({
          id,
          composite,
          head: eHead,
          maxHp: opponentMaxHp,
          name: `Bot ${i + 1}`,
        });
      }
    }

    for (const body of [...stickman_left.bodies, ...stickman_right.bodies]) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }
    touchMoveRef.current = { x: 0, y: 0 };
    setBackdropId(pickBattleBackdrop());

    setPlayer(stickman_left);
    setOpponent(stickman_right);
    setExtraBots(spawnedExtras);
    playerCompositeRef.current = stickman_left;
    opponentCompositeRef.current = stickman_right;
    playerPoseSnapRef.current = capturePoseSnapshot(stickman_left);
    opponentPoseSnapRef.current = capturePoseSnapshot(stickman_right);
    playerHead.current = head;
    opponentHead.current = botHead;
    setProtagonists([
      ...stickman_right.bodies,
      ...stickman_left.bodies,
      ...spawnedExtras.flatMap((b) => b.composite.bodies),
    ]);
    // Предметы спавним и в монстро-боях — оружие должно иметь значение везде.
    const arenaIds =
      battleConfig.kind === "lab" || battleConfig.kind === "testArena"
        ? battleConfig.arenaItemIds
        : DEFAULT_ARENA_ITEMS;
    const spawnedItems = spawnArenaItems(arenaIds, [
      ...ARENA_ITEM_SPAWN_POSITIONS,
    ]);
    itemCompositesRef.current = spawnedItems;
    setImpactComposites([
      stickman_left,
      stickman_right,
      ...spawnedExtras.map((b) => b.composite),
      ...spawnedItems,
    ]);
    battleStartRef.current = performance.now();
    {
      const allBodies = [
        ...stickman_left.bodies,
        ...stickman_right.bodies,
        ...spawnedExtras.flatMap((b) => b.composite.bodies),
        ...spawnedItems.flatMap((c) => c.bodies),
      ];
      fightTapeRef.current.begin(
        battleStartRef.current,
        allBodies.length,
        playerMaxHp,
        opponentMaxHp,
      );
    }
    const rlLoadout =
      battleConfig.kind === "roguelike"
        ? battleConfig.loadouts.you ??
          battleConfig.loadouts.player ??
          Object.values(battleConfig.loadouts)[0]
        : battleConfig.kind === "lab" || battleConfig.kind === "testArena"
          ? battleConfig.loadout
          : undefined;
    const teamMode = botCount > 1;
    const playerSpec: CoreFighterSpec = {
      id: "player",
      composite: stickman_left,
      head: head!,
      maxHp: playerMaxHp,
      // Бот бьёт игрока сильнее (×BOT_DAMAGE_MULTIPLIER); в локальном 2P буста нет.
      isBotDamageTarget: !isLocal2P,
      ...(teamMode ? { team: 0 } : {}),
      ...(rlLoadout ? { loadout: rlLoadout } : {}),
      ...(isLabLike ? { labUnlockBases: true } : {}),
      ...(battleConfig.kind === "testArena"
        ? {
            extraItems: battleConfig.extraItems,
            castAbilities: battleConfig.castAbilities,
          }
        : {}),
    };
    const opponentFighter: CoreFighterSpec = {
      id: "opponent",
      composite: stickman_right,
      head: botHead!,
      maxHp: opponentMaxHp,
      aiProfile: isLocal2P ? null : opponentSpec.aiProfile,
      defensePct: opponentSpec.defense,
      ...(teamMode ? { team: 1 } : {}),
    };
    setCoreFighters([
      playerSpec,
      opponentFighter,
      ...spawnedExtras.map(
        (b): CoreFighterSpec => ({
          id: b.id,
          composite: b.composite,
          head: b.head,
          maxHp: b.maxHp,
          team: 1,
          aiProfile: opponentSpec.aiProfile,
        }),
      ),
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
    battleConfig.kind === "roguelike" ? battleConfig.loadouts : null,
    battleConfig.kind === "lab" ? battleConfig.arenaItemIds : null,
    battleConfig.kind === "lab" ? battleConfig.loadout : null,
    battleConfig.kind === "testArena" ? battleConfig.arenaItemIds : null,
    battleConfig.kind === "testArena" ? battleConfig.loadout : null,
    battleConfig.kind === "testArena" ? battleConfig.extraItems : null,
    battleConfig.kind === "testArena" ? battleConfig.castAbilities : null,
    battleConfig.kind === "testArena" ? battleConfig.opponentCount : null,
    playerMaxHp,
    opponentMaxHp,
    opponentSpec.aiProfile,
    opponentSpec.defense,
    isLocal2P,
    isLabLike,
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
          gamepadIndex: 0,
        }
      : { gamepadIndex: 0 },
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
      gamepadIndex: isLocal2P ? 1 : null,
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
  const bloody = useBloodyParticules(
    impactComposites,
    combatFx,
    [player?.id, opponent?.id, profile.colors],
    battleOverRef,
  );
  bloodySpawnRef.current = bloody.spawnAt;
  bloodyClearRef.current = bloody.clearAll;
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
  useHitEffectClock(hitEffectsStoreRef, !showReplay);
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
      opponentHp: viewOpponentHp,
      opponentMaxHp: opponentMaxHp,
      opponentPain: painSide === "opponent",
      opponentLastHit: lastHit,
      opponentVideo: remoteOpponentFace.videoRef,
      opponentCrop: remoteOpponentFace.cropRef,
      opponentWebcamActive: remoteOpponentFace.webcamActive,
      playerPain: painSide === "player",
      webcamActive,
      faceEffect: profile.faceEffect,
      avatarFaceId: webcamActive ? undefined : profile.avatarFaceId,
      playerHp: viewPlayerHp,
      playerMaxHp: playerMaxHp,
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
      extraFighters: extraBots.map((b) => ({
        head: { current: b.head },
        composite: b.composite,
        colors: OPPONENT_COLORS,
        hud: {
          name: b.name,
          hearts: coreSession.sessionRef.current?.getHp(b.id) ?? b.maxHp,
          maxHearts: b.maxHp,
          colors: OPPONENT_COLORS,
          side: "right" as const,
        },
      })),
    },
    [
      opponentFaceForOverlay,
      opponentSpec.avatarFaceId,
      viewOpponentHp,
      opponentMaxHp,
      lastHit,
      remoteOpponentFace.webcamActive,
      remoteOpponentFace.face,
      painSide,
      playerHud,
      opponentHud,
      webcamActive,
      profile.faceEffect,
      profile.avatarFaceId,
      viewPlayerHp,
      playerMaxHp,
      lastHit,
      player,
      opponent,
      extraBots,
      settings.language,
      settings.screenEffects,
      showReplay,
      replay.playheadMs,
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
        className="battle-webcam-pip fixed bottom-4 right-4 w-24 h-18 object-cover rounded border border-gray-700 opacity-50 z-20 mirror"
        muted
        playsInline
        aria-hidden
      />
      {showBattleOnboard && !showRecap && !showReplay && (
        <BattleOnboarding
          onDismiss={() => {
            markBattleOnboardingSeen();
            setShowBattleOnboard(false);
          }}
        />
      )}
      <FullscreenToggle visible={!showRecap} />
      <HpOverlay
        battleOver={battleOver}
        showRecap={showRecap || showReplay}
        winner={winner}
        faceReady={ready}
        faceError={error}
        abilities={abilities}
        local2p={isLocal2P}
        opponentAbilities={isLocal2P ? opponentAbilities : undefined}
        controlsP2={settings.controlsP2}
        playerStatus={playerStatus}
        opponentStatus={opponentStatus}
        hitEffectsStoreRef={hitEffectsStoreRef}
        lastHit={painSide}
      />
      <VirtualBattleStick
        moveRef={touchMoveRef}
        visible={
          !battleOver && !showRecap && !showReplay && !isLocal2P && !isNetHost
        }
        cooldowns={abilities}
        onAbility={(id) => {
          if (id === "dash" || id === "flip" || id === "freeze" || id === "reset") {
            playerAbilityFlags.current[id] = true;
          }
        }}
      />
      <BattleTimer
        startRef={battleStartRef}
        battleOver={battleOver}
        showRecap={showRecap || showReplay}
      />
      {!showRecap && (
        <div
          className="battle-backdrop-label font-ui pointer-events-none"
          aria-hidden
        >
          {battleBackdropLabel(backdropId)}
          <span className="battle-backdrop-label__id">{backdropId}</span>
        </div>
      )}
      {showReplay && (
        <FightReplayHud
          wave={replay.wave}
          playheadRatio={replay.playheadRatio}
          playheadMs={replay.playheadMs}
          durationMs={replay.durationMs}
          playing={replay.playing}
          speedMode={replay.speedMode}
          speed={replay.speed}
          tapeRef={fightTapeRef}
          onTogglePlay={replay.togglePlay}
          onSpeedMode={replay.setSpeedMode}
          onSeekRatio={replay.seekRatio}
          onFinish={goToRecap}
          onClipWindow={(fromMs, toMs) => {
            replayClipEndMsRef.current = toMs;
            if (fromMs != null && replay.durationMs > 0) {
              replay.seekRatio(fromMs / Math.max(1, replay.durationMs));
            }
          }}
        />
      )}
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
      <BattleSpaceBg theme={backdropId} suddenDeath={suddenDeathActive} />
      <Viewport
        protagonists={protagonists}
        hitEffectsStore={hitEffectsStoreRef}
        suddenDeath={suddenDeathActive}
      />
      <SurroundingWalls
        thick={SIZE}
        bounds={ARENA_BOUNDS}
        options={{ render: { fillStyle: "#1c2430" } }}
      />
      {player && <Composite.add object={player} />}
      {opponent && <Composite.add object={opponent} />}
      {extraBots.map((b) => (
        <Composite.add key={b.composite.id} object={b.composite} />
      ))}
      {itemCompositesRef.current.map((item) => (
        <Composite.add key={item.id} object={item} />
      ))}
    </>
  );
}
