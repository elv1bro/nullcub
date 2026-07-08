import { HpOverlay } from "@/components/HpOverlay";
import { Viewport } from "@/components/Viewport";
import { botEmotion } from "@/face/emotions";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { useBindingPressRef } from "@/input/keyBindings";
import { useMovementVectorRef } from "@/input/movementKeys";
import { netInputFromFlags } from "@/core/abilityTick";
import { pickBanterLine, shouldSpawnBanter } from "@/i18n/banter";
import { OPPONENT_COLORS } from "@/lib/fighterColors";
import { applyPlayerColors } from "@/lib/paintStickman";
import { useBattleOverlay } from "@/lib/useBattleOverlay";
import { useBattleRecapGate } from "@/lib/useBattleRecapGate";
import { pickBanter, type BanterQuip } from "@/lib/banterQuips";
import {
  dispatchHitEffects,
  useHitEffectClock,
  createHitEffectStore,
} from "@/lib/hitEffects";
import { createPopup } from "@/lib/hitPopups";
import {
  playHitSound,
  playResultSting,
  setHeartbeatLevel,
  stereoPanForX,
  stopMusic,
} from "@/audio";
import { MAX_HP, OPPONENT_MAX_HP } from "@/lib/combat";
import { capturePoseSnapshot } from "@/lib/ragdollPoseReset";
import { usePlayerAbilities } from "@/lib/usePlayerAbilities";
import { useVictoryDefeatFx } from "@/lib/useVictoryDefeatFx";
import { e2eFail, e2eMatches, e2eOk, e2eSetPhase } from "@/dev/e2eHarness";
import { decodeBodiesOrdered, lerpBodiesOrdered } from "@/net/snapshot";
import { SnapshotInterpolator } from "@/net/snapshotBuffer";
import { makeDisplayOnlyComposites } from "@/net/displayRagdoll";
import {
  INPUT_HZ,
  type NetBattleStatePayload,
  type NetHitPayload,
} from "@/net/protocol";
import type { WsNetTransport } from "@/net/wsClient";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";
import { createStickman } from "@/utils/createStickman";
import { Composite, SurroundingWalls } from "@1.framework/matter4react";
import Matter, { Body } from "matter-js";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { SIZE } from "@/routes/LeveL1";

const ARENA_BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);

export interface DedicatedBattleViewProps {
  transport: WsNetTransport;
  fighterRole: "player" | "opponent";
  onBack?: () => void;
}

export function DedicatedBattleView({
  transport,
  fighterRole,
  onBack,
}: DedicatedBattleViewProps) {
  const { profile } = usePlayerProfile();
  const { settings, t } = useSettings();

  const fighterRoleRef = useRef(fighterRole);
  fighterRoleRef.current = fighterRole;
  const battleActiveRef = useRef(true);

  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const [hostComposite, setHostComposite] = useState<Matter.Composite>();
  const [guestComposite, setGuestComposite] = useState<Matter.Composite>();
  const [itemComposites, setItemComposites] = useState<Matter.Composite[]>([]);
  const hostHeadRef = useRef<Body>();
  const guestHeadRef = useRef<Body>();
  const orderedBodiesRef = useRef<Body[]>([]);
  const snapshotInterpRef = useRef(new SnapshotInterpolator());
  const hitEffectsStoreRef = useRef(createHitEffectStore());

  const [playerHp, setPlayerHp] = useState(MAX_HP);
  const [opponentHp, setOpponentHp] = useState(OPPONENT_MAX_HP);
  const [battleOver, setBattleOver] = useState(false);
  const [winner, setWinner] = useState<"player" | "opponent" | null>(null);
  const [playerName, setPlayerName] = useState(profile.name);
  const [opponentName, setOpponentName] = useState("Opponent");
  const [lastHit, setLastHit] = useState<"player" | "opponent" | null>(null);
  const [painSide, setPainSide] = useState<"player" | "opponent" | null>(null);
  const popupsRef = useRef<import("@/lib/hitPopups").HitPopup[]>([]);
  const banterRef = useRef<BanterQuip[]>([]);
  const popupSlotRef = useRef(0);
  const effectSlotRef = useRef(0);
  const banterSlotRef = useRef(0);
  const lastBanterAtRef = useRef(0);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const cropRef = useRef<import("@/face/faceCrop").FaceCropRect | null>(null);
  const battleOverRef = useRef(false);
  const localCompositeRef = useRef<Matter.Composite>();
  const playerCompositeRef = useRef<Matter.Composite>();
  const opponentCompositeRef = useRef<Matter.Composite>();
  const poseSnapRef = useRef<import("@/lib/ragdollPoseReset").PoseSnapshot | null>(
    null,
  );
  const abilityFlagsRef = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
  });

  const readMove = useMovementVectorRef(settings.controls, { gamepadIndex: 0 });
  const grabLRef = useBindingPressRef(settings.abilities.grabL);
  const grabRRef = useBindingPressRef(settings.abilities.grabR);
  const seqRef = useRef(0);
  const readMoveRef = useRef(readMove);
  readMoveRef.current = readMove;
  const formatDamageRef = useRef(t.hit.damage);
  formatDamageRef.current = t.hit.damage;
  const profileColorsRef = useRef(profile.colors);
  profileColorsRef.current = profile.colors;
  const languageRef = useRef(settings.language);
  languageRef.current = settings.language;
  const showBanterRef = useRef(settings.showBanter);
  showBanterRef.current = settings.showBanter;
  const matureBanterRef = useRef(settings.matureBanter);
  matureBanterRef.current = settings.matureBanter;

  const handleHit = useCallback((hit: NetHitPayload) => {
    if (!battleActiveRef.current) return;
    const role = fighterRoleRef.current;
    const localVictim: "player" | "opponent" =
      hit.victimId === role ? "player" : "opponent";
    const localAggressor: "player" | "opponent" =
      localVictim === "player" ? "opponent" : "player";
    setLastHit(localVictim);
    setPainSide(localVictim);
    setTimeout(() => setPainSide(null), 450);

    const now = performance.now();
    const victimColors =
      localVictim === "player" ? profileColorsRef.current : OPPONENT_COLORS;
    popupsRef.current.push(
      createPopup(
        hit.damage,
        formatDamageRef.current(hit.damage),
        hit.x,
        hit.y,
        now,
        localVictim,
        victimColors,
        popupSlotRef.current++,
        ARENA_BOUNDS,
      ),
    );

    if (showBanterRef.current && shouldSpawnBanter(hit.damage, now, lastBanterAtRef.current)) {
      lastBanterAtRef.current = now;
      const line = pickBanterLine(
        languageRef.current,
        matureBanterRef.current,
        localAggressor,
      );
      const head =
        localAggressor === "player"
          ? (fighterRoleRef.current === "player" ? hostHeadRef : guestHeadRef).current
          : (fighterRoleRef.current === "player" ? guestHeadRef : hostHeadRef).current;
      const anchorX = head?.position.x ?? hit.x;
      const anchorY = (head?.position.y ?? hit.y) - 22;
      const colors =
        localAggressor === "player" ? profileColorsRef.current : OPPONENT_COLORS;
      banterRef.current.push(
        pickBanter(
          line,
          localAggressor,
          anchorX,
          anchorY,
          banterSlotRef.current++,
          now,
          colors,
          { bounds: ARENA_BOUNDS, bodies: orderedBodiesRef.current, existing: banterRef.current },
        ),
      );
    }

    const store = hitEffectsStoreRef.current;
    if (store && settings.screenEffects) {
      const aggressorColors =
        localAggressor === "player" ? profileColorsRef.current : OPPONENT_COLORS;
      dispatchHitEffects(store, {
        damage: hit.damage,
        contactX: hit.x,
        contactY: hit.y,
        aggressorSide: localAggressor,
        aggressorColor: aggressorColors.main,
        aggressorColors,
        arenaHeight: SIZE,
        language: languageRef.current,
        slot: effectSlotRef.current++,
        now,
      });
    }
    playHitSound(hit.damage, stereoPanForX(hit.x, 0, SIZE));
  }, [settings.screenEffects]);

  useEffect(() => {
    battleActiveRef.current = true;
    snapshotInterpRef.current.reset();

    const offSnapshot = transport.onSnapshot((payload) => {
      if (!battleActiveRef.current) return;
      const raw = payload.bodies;
      snapshotInterpRef.current.push(
        raw instanceof Float32Array ? raw : (raw as ArrayLike<number>),
        performance.now(),
      );
    });

    const offState = transport.onBattleState((state: NetBattleStatePayload) => {
      if (!battleActiveRef.current) return;
      const role = fighterRoleRef.current;
      setPlayerHp(role === "player" ? state.playerHp : state.opponentHp);
      setOpponentHp(role === "player" ? state.opponentHp : state.playerHp);
      setBattleOver(state.battleOver);
      setWinner(
        state.winner
          ? role === "player"
            ? state.winner
            : state.winner === "player"
              ? "opponent"
              : "player"
          : null,
      );
      setPlayerName(role === "player" ? state.playerName : state.opponentName);
      setOpponentName(role === "player" ? state.opponentName : state.playerName);
    });

    const offHit = transport.onHit(handleHit);

    const inputTimer = setInterval(() => {
      if (!battleActiveRef.current || battleOverRef.current) return;
      const move = readMoveRef.current();
      const flags = abilityFlagsRef.current;
      transport.sendInput(
        netInputFromFlags(
          move,
          grabLRef.current,
          grabRRef.current,
          flags,
          seqRef.current++,
          performance.now(),
        ),
      );
      abilityFlagsRef.current = {
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      };
    }, 1000 / INPUT_HZ);

    return () => {
      battleActiveRef.current = false;
      clearInterval(inputTimer);
      offSnapshot();
      offState();
      offHit();
    };
  }, [transport, handleHit]);

  useEffect(() => {
    let raf = 0;
    const step = () => {
      const sample = snapshotInterpRef.current.sample();
      if (sample && battleActiveRef.current) {
        if (sample.mode === "single") {
          decodeBodiesOrdered(sample.data, orderedBodiesRef.current, 1, {
            positionsOnly: true,
          });
        } else {
          lerpBodiesOrdered(sample.from, sample.to, sample.alpha, sample.data);
          decodeBodiesOrdered(sample.data, orderedBodiesRef.current, 1, {
            positionsOnly: true,
          });
        }
      }
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, []);

  useEffect(() => {
    const left = createStickman((1 / 3) * SIZE, (1 / 2) * SIZE, {
      render: { fillStyle: OPPONENT_COLORS.main },
    });
    const right = createStickman((2 / 3) * SIZE, (1 / 2) * SIZE, {
      render: { fillStyle: profile.colors.main },
    });

    const meIsPlayer = fighterRole === "player";
    const myComposite = meIsPlayer ? left : right;
    applyPlayerColors(myComposite, profile.colors.main, profile.colors.secondary);
    applyPlayerColors(left, OPPONENT_COLORS.main, OPPONENT_COLORS.secondary);
    applyPlayerColors(right, profile.colors.main, profile.colors.secondary);

    const leftHead = left.bodies.find((b) => b.label === "Head");
    const rightHead = right.bodies.find((b) => b.label === "Head");
    if (leftHead) leftHead.render.visible = false;
    if (rightHead) rightHead.render.visible = false;

    for (const body of [...left.bodies, ...right.bodies]) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }

    const items = spawnArenaItems(DEFAULT_ARENA_ITEMS, [...ARENA_ITEM_SPAWN_POSITIONS]);
    makeDisplayOnlyComposites([left, right, ...items]);

    setHostComposite(left);
    setGuestComposite(right);
    setItemComposites(items);
    hostHeadRef.current = leftHead;
    guestHeadRef.current = rightHead;
    localCompositeRef.current = myComposite;
    playerCompositeRef.current = left;
    opponentCompositeRef.current = right;
    poseSnapRef.current = capturePoseSnapshot(myComposite);
    orderedBodiesRef.current = [
      ...left.bodies,
      ...right.bodies,
      ...items.flatMap((c) => c.bodies),
    ];
    setProtagonists([...left.bodies, ...right.bodies]);
  }, [profile.colors.main, profile.colors.secondary, fighterRole]);

  const meIsPlayer = fighterRole === "player";
  const localHeadRef = meIsPlayer ? hostHeadRef : guestHeadRef;
  const remoteHeadRef = meIsPlayer ? guestHeadRef : hostHeadRef;
  const localComposite = meIsPlayer ? hostComposite : guestComposite;
  const remoteComposite = meIsPlayer ? guestComposite : hostComposite;

  battleOverRef.current = battleOver;
  const showRecap = useBattleRecapGate(battleOver);

  useEffect(() => {
    if (!battleOver) return;
    stopMusic(700);
    playResultSting(winner === "player" ? "victory" : "defeat");
  }, [battleOver, winner]);

  // Сердцебиение при HP < 30%
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
    if (!e2eMatches("duel")) return;
    e2eSetPhase("running");
    if (battleOver) {
      e2eFail("duel ended early");
      return;
    }
    const t = setTimeout(() => {
      if (playerHp > 0 && opponentHp > 0 && !battleOver) {
        e2eOk({ playerHp, opponentHp, mode: "duel" });
      } else {
        e2eFail(`duel hp: ${playerHp}/${opponentHp}`);
      }
    }, 10_000);
    return () => clearTimeout(t);
  }, [playerHp, opponentHp, battleOver]);

  const abilities = usePlayerAbilities(
    localHeadRef,
    localCompositeRef,
    poseSnapRef,
    battleOverRef,
    { skipPhysics: true, abilityFlagsOut: abilityFlagsRef, gamepadIndex: 0 },
  );

  const localHud = useMemo(
    () => ({
      name: playerName,
      hearts: playerHp,
      colors: profile.colors,
      side: meIsPlayer ? ("left" as const) : ("right" as const),
    }),
    [playerHp, playerName, profile.colors, meIsPlayer],
  );

  const remoteHud = useMemo(
    () => ({
      name: opponentName,
      hearts: opponentHp,
      colors: OPPONENT_COLORS,
      side: meIsPlayer ? ("right" as const) : ("left" as const),
    }),
    [opponentHp, opponentName, meIsPlayer],
  );

  const remoteFace = useMemo(
    () => botEmotion(opponentHp, OPPONENT_MAX_HP, painSide === "opponent"),
    [opponentHp, painSide],
  );

  useHitEffectClock(hitEffectsStoreRef);
  useVictoryDefeatFx({
    battleOver,
    winner,
    screenEffects: settings.screenEffects,
    playerCompositeRef,
    opponentCompositeRef,
    hitEffectsStore: hitEffectsStoreRef,
    playerColors: profile.colors,
    opponentColors: OPPONENT_COLORS,
  });

  useBattleOverlay(
    {
      playerHead: localHeadRef,
      opponentHead: remoteHeadRef,
      ...(localComposite ? { playerComposite: localComposite } : {}),
      ...(remoteComposite ? { opponentComposite: remoteComposite } : {}),
      playerVideo: videoRef,
      playerCrop: cropRef,
      opponentFace: remoteFace,
      playerPain: painSide === "player",
      webcamActive: false,
      ...(profile.faceEffect ? { faceEffect: profile.faceEffect } : {}),
      ...(profile.avatarFaceId ? { avatarFaceId: profile.avatarFaceId } : {}),
      playerHp,
      playerMaxHp: MAX_HP,
      playerLastHit: lastHit,
      playerHud: localHud,
      opponentHud: remoteHud,
      popupsRef,
      banterRef,
      hitEffectsStore: hitEffectsStoreRef,
      language: settings.language,
    },
    [
      remoteFace,
      painSide,
      localHud,
      remoteHud,
      localComposite,
      remoteComposite,
      profile.faceEffect,
      profile.avatarFaceId,
      settings.language,
      playerHp,
      lastHit,
    ],
  );

  const playerWon = battleOver && winner === "player";

  return (
    <>
      {battleOver && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 pointer-events-auto">
          <div className="flex flex-col items-center gap-4 p-8 rounded-xl border border-gray-600 bg-dark-800 text-white">
            <h2 className="text-2xl font-bold">
              {playerWon ? t.battle.victory : t.battle.defeat}
            </h2>
            <p className="text-sm text-gray-400">{t.battle.backToMenu} · Esc</p>
            {onBack && (
              <button
                type="button"
                onClick={onBack}
                className="px-6 py-2 rounded-lg bg-gray-600 hover:bg-gray-500 font-bold"
              >
                {t.battle.backToMenu}
              </button>
            )}
          </div>
        </div>
      )}

      <HpOverlay
        battleOver={battleOver}
        showRecap={showRecap}
        winner={winner}
        faceReady
        faceError={null}
        abilities={abilities}
      />
      <Viewport protagonists={protagonists} hitEffectsStore={hitEffectsStoreRef} />
      <SurroundingWalls
        thick={SIZE}
        bounds={ARENA_BOUNDS}
        options={{ render: { fillStyle: "#333" } }}
      />
      {hostComposite && <Composite.add object={hostComposite} />}
      {guestComposite && <Composite.add object={guestComposite} />}
      {itemComposites.map((item) => (
        <Composite.add key={item.id} object={item} />
      ))}
    </>
  );
}
