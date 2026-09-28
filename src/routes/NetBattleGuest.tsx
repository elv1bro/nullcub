import { BattleSpaceBg } from "@/components/BattleSpaceBg";
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
import { applyPlayerColors } from "@/lib/paintStickman";
import { OPPONENT_COLORS } from "@/lib/fighterColors";
import { useBattleOverlay } from "@/lib/useBattleOverlay";
import { useBattleRecapGate } from "@/lib/useBattleRecapGate";
import { useHitEffectClock, createHitEffectStore } from "@/lib/hitEffects";
import { useNetFaceSync } from "@/net/useNetFaceSync";
import { useNetGuestHealth } from "@/net/useNetGuestHealth";
import {
  useNetBattleGuest,
  useNetInputSender,
  useNetPing,
} from "@/net/useNetBattle";
import { useNetRemoteFace } from "@/net/useNetRemoteFace";
import { useNetSession } from "@/net/NetSessionContext";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";
import { createStickman } from "@/utils/createStickman";
import { usePlayerAbilities } from "@/lib/usePlayerAbilities";
import { capturePoseSnapshot } from "@/lib/ragdollPoseReset";
import { Composite, SurroundingWalls } from "@1.framework/matter4react";
import Matter, { Body } from "matter-js";
import { useEffect, useMemo, useRef, useState } from "react";
import { MAX_HP, OPPONENT_MAX_HP } from "@/lib/combat";
import type { AbilityCooldownView } from "@/lib/usePlayerAbilities";
import { SIZE } from "./LeveL1";

const ARENA_BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);

/** Гость: runner выключен, позиции из snapshot хоста, input на хост. */
export function NetBattleGuest() {
  const { profile } = usePlayerProfile();
  const { t, settings } = useSettings();
  const net = useNetSession();
  const pingMs = useNetPing(true);

  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const itemCompositesRef = useRef<Matter.Composite[]>([]);
  const [hostComposite, setHostComposite] = useState<Matter.Composite>();
  const [guestComposite, setGuestComposite] = useState<Matter.Composite>();
  const hostHeadRef = useRef<Body>();
  const guestHeadRef = useRef<Body>();
  const guestCompositeRef = useRef<Matter.Composite>();
  const hitEffectsStoreRef = useRef(createHitEffectStore());
  const battleOverRef = useRef(false);
  const poseSnapRef = useRef<import("@/lib/ragdollPoseReset").PoseSnapshot | null>(
    null,
  );
  const abilityFlagsRef = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
    dropWeapon: false,
    abilitySlot: false,
  });

  const health = useNetGuestHealth(true, t.hit.damage);
  battleOverRef.current = health.battleOver;
  const showRecap = useBattleRecapGate(health.battleOver);

  const remoteHost = useNetRemoteFace(true);
  const faceMode = net.peers[0]?.faceMode ?? "video";
  const face = useNetFaceSync(faceMode, true);

  const readMove = useMovementVectorRef(settings.controls, { gamepadIndex: 0 });
  const grabLRef = useBindingPressRef(settings.abilities.grabL);
  const grabRRef = useBindingPressRef(settings.abilities.grabR);

  const abilities = usePlayerAbilities(
    guestHeadRef,
    guestCompositeRef,
    poseSnapRef,
    battleOverRef,
    { skipPhysics: true, abilityFlagsOut: abilityFlagsRef, gamepadIndex: 0 },
  );

  useNetInputSender(
    readMove,
    () => grabLRef.current,
    () => grabRRef.current,
    true,
    abilityFlagsRef,
  );

  const guestComposites = useMemo(
    () =>
      [
        ...(hostComposite ? [hostComposite] : []),
        ...(guestComposite ? [guestComposite] : []),
        ...itemCompositesRef.current,
      ],
    [hostComposite?.id, guestComposite?.id],
  );
  useNetBattleGuest(guestComposites, true);

  useEffect(() => {
    const hostSide = createStickman((1 / 3) * SIZE, (1 / 2) * SIZE, {
      render: { fillStyle: OPPONENT_COLORS.main },
    });
    applyPlayerColors(hostSide, OPPONENT_COLORS.main, OPPONENT_COLORS.secondary);

    const guestSide = createStickman((2 / 3) * SIZE, (1 / 2) * SIZE, {
      render: { fillStyle: profile.colors.main },
    });
    applyPlayerColors(
      guestSide,
      profile.colors.main,
      profile.colors.secondary,
    );

    const hostHead = hostSide.bodies.find((b) => b.label === "Head");
    const guestHead = guestSide.bodies.find((b) => b.label === "Head");
    if (hostHead) hostHead.render.visible = false;
    if (guestHead) guestHead.render.visible = false;

    for (const body of [...hostSide.bodies, ...guestSide.bodies]) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }

    setHostComposite(hostSide);
    setGuestComposite(guestSide);
    hostHeadRef.current = hostHead;
    guestHeadRef.current = guestHead;
    guestCompositeRef.current = guestSide;
    poseSnapRef.current = capturePoseSnapshot(guestSide);
    setProtagonists([...hostSide.bodies, ...guestSide.bodies]);

    const spawnedItems = spawnArenaItems(DEFAULT_ARENA_ITEMS, [
      ...ARENA_ITEM_SPAWN_POSITIONS,
    ]);
    itemCompositesRef.current = spawnedItems;
  }, [profile.colors.main, profile.colors.secondary]);

  const [painSide, setPainSide] = useState<"player" | "opponent" | null>(null);
  useEffect(() => {
    if (!health.lastHit) return;
    setPainSide(health.lastHit);
    const timer = setTimeout(() => setPainSide(null), 450);
    return () => clearTimeout(timer);
  }, [health.lastHit, health.playerHp, health.opponentHp]);

  const hostFace = useMemo(() => {
    if (remoteHost.webcamActive) return null;
    return botEmotion(
      health.opponentHp,
      OPPONENT_MAX_HP,
      painSide === "opponent",
    );
  }, [remoteHost.webcamActive, health.opponentHp, painSide]);

  const guestHud = useMemo(
    () => ({
      name: health.playerName || profile.name,
      hearts: health.playerHp,
      maxHearts: MAX_HP,
      colors: profile.colors,
      side: "right" as const,
    }),
    [health.playerHp, health.playerName, profile.name, profile.colors],
  );

  const hostHud = useMemo(
    () => ({
      name: health.opponentName || remoteHost.peerName || "Host",
      hearts: health.opponentHp,
      maxHearts: OPPONENT_MAX_HP,
      colors: OPPONENT_COLORS,
      side: "left" as const,
    }),
    [health.opponentHp, health.opponentName, remoteHost.peerName],
  );

  const webcamActive = profile.useCamera && face.ready && !face.error;

  useHitEffectClock(hitEffectsStoreRef);
  useBattleOverlay(
    {
      playerHead: guestHeadRef,
      opponentHead: hostHeadRef,
      playerComposite: guestComposite,
      opponentComposite: hostComposite,
      playerVideo: face.videoRef,
      playerCrop: face.cropRef,
      opponentFace: hostFace,
      opponentVideo: remoteHost.videoRef,
      opponentCrop: remoteHost.cropRef,
      opponentWebcamActive: remoteHost.webcamActive,
      playerPain: painSide === "player",
      webcamActive,
      faceEffect: profile.faceEffect,
      avatarFaceId: profile.avatarFaceId,
      playerHud: guestHud,
      opponentHud: hostHud,
      popupsRef: health.popupsRef,
      hitEffectsStore: hitEffectsStoreRef,
      language: settings.language,
    },
    [
      hostFace,
      painSide,
      guestHud,
      hostHud,
      webcamActive,
      profile.faceEffect,
      profile.avatarFaceId,
      guestComposite,
      hostComposite,
      settings.language,
      remoteHost.webcamActive,
    ],
  );

  const inputBlockedRef = useRef(false);
  inputBlockedRef.current = health.battleOver;
  const guestAbilities: AbilityCooldownView = abilities;

  return (
    <>
      <div className="fixed top-2 right-2 z-30 text-xs text-gray-400 font-ui pointer-events-none">
        GUEST · {pingMs > 0 ? `${pingMs}ms` : "…"}
      </div>
      <video
        ref={face.videoRef}
        className="fixed bottom-4 right-4 w-24 h-18 object-cover rounded border border-gray-700 opacity-50 z-20 mirror"
        muted
        playsInline
        aria-hidden
      />
      <HpOverlay
        battleOver={health.battleOver}
        showRecap={showRecap}
        winner={health.winner}
        faceReady={face.ready}
        faceError={face.error}
        abilities={guestAbilities}
        playerStatus={{
          name: health.playerName || profile.name,
          hp: health.playerHp,
          maxHp: MAX_HP,
          color: profile.colors.main,
          secondaryColor: profile.colors.secondary,
        }}
        opponentStatus={{
          name: health.opponentName || remoteHost.peerName || "Host",
          hp: health.opponentHp,
          maxHp: OPPONENT_MAX_HP,
          color: OPPONENT_COLORS.main,
          secondaryColor: OPPONENT_COLORS.secondary,
        }}
      />
      <BattleSpaceBg />
      <Viewport protagonists={protagonists} hitEffectsStore={hitEffectsStoreRef} />
      <SurroundingWalls
        thick={SIZE}
        bounds={ARENA_BOUNDS}
        options={{ render: { fillStyle: "#1c2430" } }}
      />
      {hostComposite && <Composite.add object={hostComposite} />}
      {guestComposite && <Composite.add object={guestComposite} />}
      {itemCompositesRef.current.map((item) => (
        <Composite.add key={item.id} object={item} />
      ))}
    </>
  );
}
