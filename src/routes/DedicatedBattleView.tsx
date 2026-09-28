import { HpOverlay } from "@/components/HpOverlay";
import { BattleSpaceBg } from "@/components/BattleSpaceBg";
import { Viewport } from "@/components/Viewport";
import { botEmotion } from "@/face/emotions";
import {
  ARENA_ITEM_SPAWN_POSITIONS,
  DEFAULT_ARENA_ITEMS,
  spawnArenaItems,
} from "@/items";
import { useBindingPressRef } from "@/input/keyBindings";
import { useMovementVectorRef } from "@/input/movementKeys";
import { formatKeyLabel } from "@/input/PlayerMovementInput";
import { netInputFromFlags } from "@/core/abilityTick";
import { pickBanterLine, shouldSpawnBanter } from "@/i18n/banter";
import { colorsForSlot, OPPONENT_COLORS } from "@/lib/fighterColors";
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
import type { WsLobbyPlayer } from "@/net/transport";
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
  /** Основной fighterId этого клиента. */
  fighterRole: string;
  /** Все fighterId на сокете (хост + локальный). */
  ownedFighterIds?: string[];
  /** Порядок тел в снапшоте (= start.fighterIds). */
  battleFighterIds?: string[];
  lobby?: WsLobbyPlayer[];
  onBack?: () => void;
}

type DisplayFighter = {
  id: string;
  composite: Matter.Composite;
  head: Body | undefined;
  colors: ReturnType<typeof colorsForSlot>;
  owned: boolean;
};

function resolveFighterIds(
  battleFighterIds: string[] | undefined,
  lobby: WsLobbyPlayer[] | undefined,
): string[] {
  if (battleFighterIds?.length) return battleFighterIds;
  if (lobby?.length) return lobby.map((p) => p.fighterId);
  return ["player", "opponent"];
}

export function DedicatedBattleView({
  transport,
  fighterRole,
  ownedFighterIds: ownedProp,
  battleFighterIds: battleIdsProp,
  lobby,
  onBack,
}: DedicatedBattleViewProps) {
  const { profile } = usePlayerProfile();
  const { settings, t } = useSettings();

  const ownedFighterIds = ownedProp?.length ? ownedProp : [fighterRole];
  const fighterIds = resolveFighterIds(battleIdsProp, lobby);

  const fighterRoleRef = useRef(fighterRole);
  fighterRoleRef.current = fighterRole;
  const ownedRef = useRef(ownedFighterIds);
  ownedRef.current = ownedFighterIds;
  const battleActiveRef = useRef(true);

  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const [displayFighters, setDisplayFighters] = useState<DisplayFighter[]>([]);
  const [itemComposites, setItemComposites] = useState<Matter.Composite[]>([]);
  const headsByIdRef = useRef<Record<string, Body | undefined>>({});
  const compositesByIdRef = useRef<Record<string, Matter.Composite>>({});
  const orderedBodiesRef = useRef<Body[]>([]);
  const snapshotInterpRef = useRef(new SnapshotInterpolator());
  const hitEffectsStoreRef = useRef(createHitEffectStore());

  const [hps, setHps] = useState<Record<string, number>>({});
  const [battleOver, setBattleOver] = useState(false);
  const [winnerId, setWinnerId] = useState<string | null>(null);
  const [winnerTeam, setWinnerTeam] = useState<number | null>(null);
  const [names, setNames] = useState<Record<string, string>>({});
  const [lastHitId, setLastHitId] = useState<string | null>(null);
  const [painId, setPainId] = useState<string | null>(null);
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
    dropWeapon: false,
    abilitySlot: false,
  });
  const abilityFlagsP2Ref = useRef({
    dash: false,
    flip: false,
    freeze: false,
    reset: false,
    dropWeapon: false,
    abilitySlot: false,
  });

  const readMove = useMovementVectorRef(settings.controls, { gamepadIndex: 0 });
  const readMoveP2 = useMovementVectorRef(settings.controlsP2, {
    gamepadIndex: 1,
  });
  const grabLRef = useBindingPressRef(settings.abilities.grabL);
  const grabRRef = useBindingPressRef(settings.abilities.grabR);
  const grabL2Ref = useBindingPressRef(settings.abilitiesP2.grabL);
  const grabR2Ref = useBindingPressRef(settings.abilitiesP2.grabR);
  const seqRef = useRef(0);
  const seqP2Ref = useRef(0);
  const readMoveRef = useRef(readMove);
  readMoveRef.current = readMove;
  const readMoveP2Ref = useRef(readMoveP2);
  readMoveP2Ref.current = readMoveP2;
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

  const primaryId = fighterRole;
  const secondaryOwned =
    ownedFighterIds.find((id) => id !== primaryId) ?? null;

  const handleHit = useCallback(
    (hit: NetHitPayload) => {
      if (!battleActiveRef.current) return;
      const owned = ownedRef.current;
      const localVictim = owned.includes(hit.victimId);
      setLastHitId(hit.victimId);
      setPainId(hit.victimId);
      setTimeout(() => setPainId(null), 450);

      const now = performance.now();
      const idx = fighterIds.indexOf(hit.victimId);
      const victimColors =
        hit.victimId === fighterRoleRef.current
          ? profileColorsRef.current
          : colorsForSlot(idx >= 0 ? idx : 1);
      popupsRef.current.push(
        createPopup(
          hit.damage,
          formatDamageRef.current(hit.damage),
          hit.x,
          hit.y,
          now,
          localVictim ? "player" : "opponent",
          victimColors,
          popupSlotRef.current++,
          ARENA_BOUNDS,
        ),
      );

      if (
        showBanterRef.current &&
        shouldSpawnBanter(hit.damage, now, lastBanterAtRef.current)
      ) {
        lastBanterAtRef.current = now;
        const aggressorSide = localVictim ? "opponent" : "player";
        const line = pickBanterLine(
          languageRef.current,
          matureBanterRef.current,
          aggressorSide,
        );
        const head = headsByIdRef.current[hit.victimId];
        const anchorX = head?.position.x ?? hit.x;
        const anchorY = (head?.position.y ?? hit.y) - 22;
        banterRef.current.push(
          pickBanter(
            line,
            aggressorSide,
            anchorX,
            anchorY,
            banterSlotRef.current++,
            now,
            victimColors,
            {
              bounds: ARENA_BOUNDS,
              bodies: orderedBodiesRef.current,
              existing: banterRef.current,
            },
          ),
        );
      }

      const store = hitEffectsStoreRef.current;
      if (store && settings.screenEffects) {
        dispatchHitEffects(store, {
          damage: hit.damage,
          contactX: hit.x,
          contactY: hit.y,
          aggressorSide: localVictim ? "opponent" : "player",
          aggressorColor: victimColors.main,
          aggressorColors: victimColors,
          arenaHeight: SIZE,
          language: languageRef.current,
          slot: effectSlotRef.current++,
          now,
        });
      }
      playHitSound(hit.damage, stereoPanForX(hit.x, 0, SIZE));
    },
    [fighterIds, settings.screenEffects],
  );

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
      if (state.hps && Object.keys(state.hps).length) {
        setHps(state.hps);
      } else {
        setHps({
          player: state.playerHp,
          opponent: state.opponentHp,
        });
      }
      setBattleOver(state.battleOver);
      setWinnerTeam(state.winnerTeam ?? null);
      setWinnerId(state.winner ? String(state.winner) : null);
      setNames((prev) => ({
        ...prev,
        player: state.playerName || prev.player || "Player",
        opponent: state.opponentName || prev.opponent || "Opponent",
      }));
    });

    const offHit = transport.onHit(handleHit);

    const inputTimer = setInterval(() => {
      if (!battleActiveRef.current || battleOverRef.current) return;
      const owned = ownedRef.current;
      const primary = fighterRoleRef.current;
      const flags = abilityFlagsRef.current;
      transport.sendInput(
        netInputFromFlags(
          readMoveRef.current(),
          grabLRef.current,
          grabRRef.current,
          flags,
          seqRef.current++,
          performance.now(),
        ),
        primary,
      );
      abilityFlagsRef.current = {
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
    dropWeapon: false,
    abilitySlot: false,
      };

      const second = owned.find((id) => id !== primary);
      if (second) {
        const flags2 = abilityFlagsP2Ref.current;
        transport.sendInput(
          netInputFromFlags(
            readMoveP2Ref.current(),
            grabL2Ref.current,
            grabR2Ref.current,
            flags2,
            seqP2Ref.current++,
            performance.now(),
          ),
          second,
        );
        abilityFlagsP2Ref.current = {
          dash: false,
          flip: false,
          freeze: false,
          reset: false,
    dropWeapon: false,
    abilitySlot: false,
        };
      }
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
    const ids = fighterIds;
    const n = ids.length;
    const created: DisplayFighter[] = ids.map((id, i) => {
      const x = ((i + 1) / (n + 1)) * SIZE;
      const colors =
        id === fighterRole ? profile.colors : colorsForSlot(i);
      const composite = createStickman(x, (1 / 2) * SIZE, {
        render: { fillStyle: colors.main },
      });
      applyPlayerColors(composite, colors.main, colors.secondary);
      const head = composite.bodies.find((b) => b.label === "Head");
      if (head) head.render.visible = false;
      for (const body of composite.bodies) {
        Body.setVelocity(body, { x: 0, y: 0 });
        Body.setAngularVelocity(body, 0);
      }
      return {
        id,
        composite,
        head,
        colors,
        owned: ownedFighterIds.includes(id),
      };
    });

    const items = spawnArenaItems(DEFAULT_ARENA_ITEMS, [
      ...ARENA_ITEM_SPAWN_POSITIONS,
    ]);
    makeDisplayOnlyComposites([
      ...created.map((f) => f.composite),
      ...items,
    ]);

    const heads: Record<string, Body | undefined> = {};
    const comps: Record<string, Matter.Composite> = {};
    for (const f of created) {
      heads[f.id] = f.head;
      comps[f.id] = f.composite;
    }
    headsByIdRef.current = heads;
    compositesByIdRef.current = comps;

    const primary = created.find((f) => f.id === fighterRole) ?? created[0];
    const secondary =
      created.find((f) => f.id !== fighterRole && f.owned) ??
      created.find((f) => f.id !== fighterRole);

    localCompositeRef.current = primary?.composite;
    playerCompositeRef.current = primary?.composite;
    opponentCompositeRef.current = secondary?.composite;
    poseSnapRef.current = primary
      ? capturePoseSnapshot(primary.composite)
      : null;

    orderedBodiesRef.current = [
      ...created.flatMap((f) => f.composite.bodies),
      ...items.flatMap((c) => c.bodies),
    ];
    setDisplayFighters(created);
    setItemComposites(items);
    setProtagonists(created.flatMap((f) => f.composite.bodies));
    setHps((prev) => {
      const next = { ...prev };
      for (let i = 0; i < ids.length; i++) {
        const id = ids[i]!;
        if (next[id] == null) next[id] = i === 0 ? MAX_HP : OPPONENT_MAX_HP;
      }
      return next;
    });
    setNames((prev) => {
      const next = { ...prev };
      for (const p of lobby ?? []) next[p.fighterId] = p.name;
      if (!next[fighterRole]) next[fighterRole] = profile.name;
      return next;
    });
  }, [
    fighterIds.join("|"),
    ownedFighterIds.join("|"),
    fighterRole,
    profile.colors.main,
    profile.colors.secondary,
    profile.name,
    lobby,
  ]);

  battleOverRef.current = battleOver;
  const showRecap = useBattleRecapGate(battleOver && fighterIds.length <= 2);

  const primaryHp = hps[primaryId] ?? MAX_HP;
  const iWon =
    battleOver &&
    (winnerId != null && ownedFighterIds.includes(winnerId)
      ? true
      : winnerTeam != null
        ? (lobby?.find((p) => p.fighterId === primaryId)?.team ?? 0) ===
          winnerTeam
        : winnerId === "player" && primaryId === "player");

  useEffect(() => {
    if (!battleOver) return;
    stopMusic(700);
    playResultSting(iWon ? "victory" : "defeat");
  }, [battleOver, iWon]);

  useEffect(() => {
    if (battleOver) {
      setHeartbeatLevel(0);
      return;
    }
    const ratio = primaryHp / MAX_HP;
    setHeartbeatLevel(ratio < 0.3 ? (0.3 - ratio) / 0.3 : 0);
  }, [primaryHp, battleOver]);

  useEffect(() => () => setHeartbeatLevel(0), []);

  useEffect(() => {
    if (!e2eMatches("duel")) return;
    e2eSetPhase("running");
    if (battleOver) {
      e2eFail("duel ended early");
      return;
    }
    const t = setTimeout(() => {
      const alive = Object.values(hps).every((hp) => hp > 0);
      if (alive && !battleOver) {
        e2eOk({
          playerHp: primaryHp,
          opponentHp: hps.opponent ?? hps[fighterIds[1] ?? ""] ?? 0,
          mode: "duel",
          fighters: fighterIds.length,
        });
      } else {
        e2eFail(`duel hp fail`);
      }
    }, 10_000);
    return () => clearTimeout(t);
  }, [hps, battleOver, primaryHp, fighterIds]);

  const primaryHeadRef = useRef<Body | undefined>();
  primaryHeadRef.current = headsByIdRef.current[primaryId];
  const remoteHeadRef = useRef<Body | undefined>();
  const localP2HeadRef = useRef<Body | undefined>();
  const remoteId =
    fighterIds.find((id) => !ownedFighterIds.includes(id)) ??
    fighterIds.find((id) => id !== primaryId) ??
    "opponent";
  remoteHeadRef.current = headsByIdRef.current[remoteId];
  localP2HeadRef.current = secondaryOwned
    ? headsByIdRef.current[secondaryOwned]
    : undefined;

  const abilities = usePlayerAbilities(
    primaryHeadRef,
    localCompositeRef,
    poseSnapRef,
    battleOverRef,
    { skipPhysics: true, abilityFlagsOut: abilityFlagsRef, gamepadIndex: 0 },
  );

  const secondaryCompositeRef = useRef<Matter.Composite>();
  secondaryCompositeRef.current = secondaryOwned
    ? compositesByIdRef.current[secondaryOwned]
    : undefined;
  const poseSnapP2Ref = useRef<import("@/lib/ragdollPoseReset").PoseSnapshot | null>(
    null,
  );
  useEffect(() => {
    if (secondaryOwned && compositesByIdRef.current[secondaryOwned]) {
      poseSnapP2Ref.current = capturePoseSnapshot(
        compositesByIdRef.current[secondaryOwned]!,
      );
    }
  }, [secondaryOwned, displayFighters]);

  const abilitiesP2 = usePlayerAbilities(
    localP2HeadRef,
    secondaryCompositeRef,
    poseSnapP2Ref,
    battleOverRef,
    {
      skipPhysics: true,
      abilityFlagsOut: abilityFlagsP2Ref,
      gamepadIndex: 1,
      enabled: Boolean(secondaryOwned),
    },
  );

  const primaryHud = useMemo(
    () => ({
      name: names[primaryId] ?? profile.name,
      hearts: primaryHp,
      maxHearts: MAX_HP,
      colors: profile.colors,
      side: "left" as const,
    }),
    [names, primaryId, primaryHp, profile.name, profile.colors],
  );

  const remoteHud = useMemo(
    () => ({
      name: names[remoteId] ?? "Opponent",
      hearts: hps[remoteId] ?? OPPONENT_MAX_HP,
      maxHearts: OPPONENT_MAX_HP,
      colors: colorsForSlot(Math.max(0, fighterIds.indexOf(remoteId))),
      side: "right" as const,
    }),
    [names, remoteId, hps, fighterIds],
  );

  const playerStatus = useMemo(
    () => ({
      name: names[primaryId] ?? profile.name,
      hp: primaryHp,
      maxHp: MAX_HP,
      color: profile.colors.main,
      secondaryColor: profile.colors.secondary,
    }),
    [names, primaryId, primaryHp, profile.name, profile.colors],
  );

  const opponentStatus = useMemo(() => {
    const colors = colorsForSlot(Math.max(0, fighterIds.indexOf(remoteId)));
    return {
      name: names[remoteId] ?? "Opponent",
      hp: hps[remoteId] ?? OPPONENT_MAX_HP,
      maxHp: OPPONENT_MAX_HP,
      color: colors.main,
      secondaryColor: colors.secondary,
    };
  }, [names, remoteId, hps, fighterIds]);

  const extraFighters = useMemo(() => {
    return fighterIds
      .filter((id) => id !== primaryId && id !== remoteId)
      .map((id) => {
        const idx = fighterIds.indexOf(id);
        const headRef = { current: headsByIdRef.current[id] };
        const hp = hps[id] ?? OPPONENT_MAX_HP;
        return {
          head: headRef,
          hud: {
            name: names[id] ?? id,
            hearts: hp,
            maxHearts: OPPONENT_MAX_HP,
            colors: colorsForSlot(idx),
            side: "right" as const,
          },
          face: botEmotion(hp, OPPONENT_MAX_HP, painId === id),
          pain: painId === id,
          colors: colorsForSlot(idx),
          composite: compositesByIdRef.current[id],
        };
      });
  }, [fighterIds, primaryId, remoteId, hps, names, painId, displayFighters]);

  const remoteFace = useMemo(
    () =>
      botEmotion(
        hps[remoteId] ?? OPPONENT_MAX_HP,
        OPPONENT_MAX_HP,
        painId === remoteId,
      ),
    [hps, remoteId, painId],
  );

  useHitEffectClock(hitEffectsStoreRef);
  useVictoryDefeatFx({
    battleOver,
    winner: iWon ? "player" : battleOver ? "opponent" : null,
    screenEffects: settings.screenEffects,
    playerCompositeRef,
    opponentCompositeRef,
    hitEffectsStore: hitEffectsStoreRef,
    playerColors: profile.colors,
    opponentColors: OPPONENT_COLORS,
  });

  const primaryComposite = compositesByIdRef.current[primaryId];
  const remoteComposite = compositesByIdRef.current[remoteId];

  useBattleOverlay(
    {
      playerHead: primaryHeadRef,
      opponentHead: remoteHeadRef,
      ...(primaryComposite ? { playerComposite: primaryComposite } : {}),
      ...(remoteComposite ? { opponentComposite: remoteComposite } : {}),
      playerVideo: videoRef,
      playerCrop: cropRef,
      opponentFace: remoteFace,
      playerPain: painId === primaryId,
      webcamActive: false,
      ...(profile.faceEffect ? { faceEffect: profile.faceEffect } : {}),
      ...(profile.avatarFaceId ? { avatarFaceId: profile.avatarFaceId } : {}),
      playerHp: primaryHp,
      playerMaxHp: MAX_HP,
      playerLastHit: lastHitId === primaryId ? "player" : lastHitId ? "opponent" : null,
      playerHud: primaryHud,
      opponentHud: remoteHud,
      extraFighters,
      popupsRef,
      banterRef,
      hitEffectsStore: hitEffectsStoreRef,
      language: settings.language,
    },
    [
      remoteFace,
      painId,
      primaryHud,
      remoteHud,
      primaryComposite,
      remoteComposite,
      profile.faceEffect,
      profile.avatarFaceId,
      settings.language,
      primaryHp,
      lastHitId,
      extraFighters,
    ],
  );

  const fighterBars = useMemo(() => {
    if (!secondaryOwned) return undefined;
    return [
      {
        id: primaryId,
        label: names[primaryId] ?? t.battle.player1,
        abilities,
        moveHint: `${formatKeyLabel(settings.controls.up)}${formatKeyLabel(settings.controls.left)}${formatKeyLabel(settings.controls.down)}${formatKeyLabel(settings.controls.right)}`,
        hp: primaryHp,
        maxHp: MAX_HP,
        color: profile.colors.main,
      },
      {
        id: secondaryOwned,
        label: names[secondaryOwned] ?? t.battle.player2,
        abilities: abilitiesP2,
        bindings: settings.abilitiesP2,
        moveHint: `${formatKeyLabel(settings.controlsP2.up)}${formatKeyLabel(settings.controlsP2.left)}${formatKeyLabel(settings.controlsP2.down)}${formatKeyLabel(settings.controlsP2.right)}`,
        hp: hps[secondaryOwned] ?? MAX_HP,
        maxHp: MAX_HP,
        color: colorsForSlot(1).main,
      },
    ];
  }, [
    secondaryOwned,
    primaryId,
    names,
    t.battle.player1,
    t.battle.player2,
    abilities,
    abilitiesP2,
    settings.controls,
    settings.controlsP2,
    settings.abilitiesP2,
    primaryHp,
    hps,
    profile.colors.main,
  ]);

  return (
    <>
      {battleOver && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 pointer-events-auto">
          <div className="flex flex-col items-center gap-4 p-8 rounded-xl border border-gray-600 bg-dark-800 text-white">
            <h2 className="text-2xl font-bold">
              {iWon ? t.battle.victory : t.battle.defeat}
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
        winner={iWon ? "player" : battleOver ? "opponent" : null}
        faceReady
        faceError={null}
        abilities={abilities}
        fighterBars={fighterBars}
        playerStatus={playerStatus}
        opponentStatus={opponentStatus}
      />
      <BattleSpaceBg />
      <Viewport protagonists={protagonists} hitEffectsStore={hitEffectsStoreRef} />
      <SurroundingWalls
        thick={SIZE}
        bounds={ARENA_BOUNDS}
        options={{ render: { fillStyle: "#1c2430" } }}
      />
      {displayFighters.map((f) => (
        <Composite.add key={f.id} object={f.composite} />
      ))}
      {itemComposites.map((item) => (
        <Composite.add key={item.id} object={item} />
      ))}
    </>
  );
}
