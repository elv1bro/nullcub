import { MenuArenaViewport } from "@/components/menu/MenuArenaViewport";
import { MENU_ARENA_H, MENU_ARENA_W } from "@/lib/menuArenaConstants";
import { useFaceTracker } from "@/face/tracker";
import { useBattleOverlay } from "@/lib/useBattleOverlay";
import {
  clearMenuChains,
  createMenuChains,
  MENU_CHAIN_COUNT,
  syncMenuChains,
  type MenuChainSet,
} from "@/lib/menuChains";
import {
  pruneEscapeQuips,
  spawnEscapeQuip,
  type EscapeQuip,
} from "@/lib/menuEscapeQuips";
import {
  drawChainBreakFx,
  pruneChainBreakFx,
  spawnChainBreakFx,
  type ChainBreakFx,
} from "@/lib/menuChainBreakFx";
import { holdPoseSnapshot, capturePoseSnapshot, type PoseSnapshot } from "@/lib/ragdollPoseReset";
import { menuPlatformY, zeroMenuRagdollVelocities } from "@/lib/menuStance";
import { applyPlayerColors } from "@/lib/paintStickman";
import { playChainBreakSound } from "@/audio";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import {
  drawEscapeQuips,
  drawMenuArenaTitle,
  drawMenuChains,
} from "@/render/drawMenuArenaOverlay";
import { useSettings } from "@/settings/SettingsContext";
import { createStickman } from "@/utils/createStickman";
import {
  Composite,
  Rectangle,
  SurroundingWalls,
  useEngine,
  useEventBeforeUpdate,
  useRender,
  useRenderEvent,
} from "@1.framework/matter4react";
import Matter, { Body, type Composite as MatterComposite } from "matter-js";
import { useEffect, useLayoutEffect, useRef, useState } from "react";

export type MenuPlayPhase = "idle" | "partial" | "soaring";

interface Props {
  playPhase: MenuPlayPhase;
  playRunId: number;
  chainsBroken: number;
}

export function MenuArenaScene({ playPhase, playRunId, chainsBroken }: Props) {
  const { profile } = usePlayerProfile();
  const { t, settings } = useSettings();
  const engine = useEngine();
  const { ready, error, videoRef, cropRef } = useFaceTracker({
    enabled: profile.useCamera,
    audio: profile.useMicrophone,
    tracking: false,
  });
  const webcamActive = profile.useCamera && ready && !error;

  const [player, setPlayer] = useState<MatterComposite>();
  const playerHeadRef = useRef<Body>();
  const chainSetRef = useRef<MenuChainSet | null>(null);
  const escapeQuipsRef = useRef<EscapeQuip[]>([]);
  const chainBreakFxRef = useRef<ChainBreakFx[]>([]);
  const quipSlotRef = useRef(0);
  const prevBrokenRef = useRef(0);
  const chainsBrokenRef = useRef(chainsBroken);
  chainsBrokenRef.current = chainsBroken;
  const playPhaseRef = useRef(playPhase);
  playPhaseRef.current = playPhase;
  const menuPoseSnapRef = useRef<PoseSnapshot | null>(null);

  const spawnX = MENU_ARENA_W * 0.28;
  const spawnY = MENU_ARENA_H * 0.52;

  useEffect(() => {
    if (!engine) return;

    const p = createStickman(spawnX, spawnY, {
      render: { fillStyle: profile.colors.main },
    });
    applyPlayerColors(p, profile.colors.main, profile.colors.secondary);

    const head = p.bodies.find((b) => b.label === "Head");
    if (head) head.render.visible = false;
    playerHeadRef.current = head;

    zeroMenuRagdollVelocities(p);
    chainSetRef.current = createMenuChains(p, spawnX, spawnY);
    syncMenuChains(chainSetRef.current, p, chainsBrokenRef.current);
    prevBrokenRef.current = chainsBrokenRef.current;
    // Сразу фиксируем позу — иначе на home ragdoll крутится без смысла.
    menuPoseSnapRef.current = capturePoseSnapshot(p);
    setPlayer(p);

    return () => {
      if (chainSetRef.current) clearMenuChains(chainSetRef.current, p);
      setPlayer(undefined);
      playerHeadRef.current = undefined;
      chainSetRef.current = null;
      menuPoseSnapRef.current = null;
    };
  }, [engine, spawnX, spawnY]);

  useEffect(() => {
    prevBrokenRef.current = 0;
  }, [playRunId]);

  // Idle / возврат домой: короткая усадка → свежий снимок стойки.
      // Partial: отпускаем позу, чтобы рывок с цепью был живым.
  useEffect(() => {
    if (!player) return;
    if (playPhase === "partial") {
      menuPoseSnapRef.current = null;
      return;
    }
    zeroMenuRagdollVelocities(player);
    let frames = 0;
    let raf = 0;
    const settle = () => {
      frames += 1;
      zeroMenuRagdollVelocities(player);
      if (frames < 18) {
        raf = requestAnimationFrame(settle);
        return;
      }
      menuPoseSnapRef.current = capturePoseSnapshot(player);
    };
    raf = requestAnimationFrame(settle);
    return () => cancelAnimationFrame(raf);
  }, [player, playPhase, playRunId]);

  useEffect(() => {
    if (!player) return;
    applyPlayerColors(player, profile.colors.main, profile.colors.secondary);
  }, [player, profile.colors.main, profile.colors.secondary]);

  useEffect(() => {
    escapeQuipsRef.current = [];
    chainBreakFxRef.current = [];
  }, [playRunId]);

  useLayoutEffect(() => {
    if (!player || !chainSetRef.current) return;

    const prev = prevBrokenRef.current;
    const wantRemaining = Math.max(0, MENU_CHAIN_COUNT - chainsBroken);
    const hasMismatch = chainSetRef.current.links.length !== wantRemaining;

    if (!hasMismatch) {
      prevBrokenRef.current = chainsBroken;
      return;
    }

    const breakEvents = syncMenuChains(
      chainSetRef.current,
      player,
      chainsBroken,
    );

    const userBrokeMore = chainsBroken > prev;
    if (breakEvents.length > 0 && userBrokeMore) {
      playChainBreakSound();
      const now = performance.now();
      for (const evt of breakEvents) {
        spawnChainBreakFx(chainBreakFxRef.current, evt, now);
      }
    }

    if (chainsBroken === 0 && prev > 0) {
      escapeQuipsRef.current = [];
      chainBreakFxRef.current = [];
    }

    if (chainsBroken === 1 && prev < 1) {
      spawnEscapeQuip(
        escapeQuipsRef.current,
        settings.language,
        performance.now(),
        quipSlotRef.current++,
      );
    }

    if (chainsBroken >= 2 && player) {
      zeroMenuRagdollVelocities(player);
      menuPoseSnapRef.current = capturePoseSnapshot(player);
    }
    // chainsBroken < 2 на home (idle) — позу держит отдельный idle-settle effect.
    // В partial snap уже сброшен через playPhase.

    prevBrokenRef.current = chainsBroken;
  }, [chainsBroken, player, settings.language]);

  useEventBeforeUpdate(
    () => {
      if (!player) return;
      // В partial — живая физика (одна цепь). Иначе держим витрину бойца.
      if (playPhaseRef.current === "partial") return;
      const snap = menuPoseSnapRef.current;
      if (!snap) return;
      holdPoseSnapshot(player, snap);

      if (playPhaseRef.current !== "idle") return;
      const head = playerHeadRef.current;
      if (!head) return;
      // Лёгкое покачивание — «живой», но не кувырок.
      const sway = Math.sin(performance.now() / 1400) * 5;
      const targetX = spawnX + sway;
      Body.translate(head, {
        x: (targetX - head.position.x) * 0.04,
        y: 0,
      });
      Body.setAngularVelocity(head, head.angularVelocity * 0.85);
    },
    [player, spawnX],
  );

  useEffect(() => {
    if (playPhase !== "partial" || !player) return;

    const quipId = setInterval(() => {
      spawnEscapeQuip(
        escapeQuipsRef.current,
        settings.language,
        performance.now(),
        quipSlotRef.current++,
      );
    }, 2200);

    return () => clearInterval(quipId);
  }, [playPhase, player, settings.language]);

  useBattleOverlay(
    {
      playerHead: playerHeadRef,
      playerComposite: player,
      playerVideo: videoRef,
      playerCrop: cropRef,
      playerPain: false,
      webcamActive,
      faceEffect: profile.faceEffect,
      avatarFaceId: profile.avatarFaceId,
      playerColors: profile.colors,
      playerHud: null,
    },
    [
      webcamActive,
      player,
      profile.colors.main,
      profile.colors.secondary,
      profile.faceEffect,
      profile.avatarFaceId,
    ],
  );

  const bounds = Matter.Bounds.create([
    { x: 0, y: 0 },
    { x: MENU_ARENA_W, y: MENU_ARENA_H },
  ]);

  return (
    <>
      <MenuArenaDraw
        titleLine1={t.game.title}
        titleLine2={t.game.titleAccent}
        accentColor={profile.colors.main}
        chainSetRef={chainSetRef}
        player={player}
        escapeQuipsRef={escapeQuipsRef}
        chainBreakFxRef={chainBreakFxRef}
        headRef={playerHeadRef}
      />
      <MenuArenaViewport />
      <SurroundingWalls
        thick={80}
        bounds={bounds}
        options={{ render: { fillStyle: "#14141c", visible: false } }}
      />
      <Rectangle
        x={spawnX}
        y={menuPlatformY(spawnY)}
        width={140}
        height={20}
        options={{
          isStatic: true,
          label: "MenuPlatform",
          render: { visible: false },
        }}
      />
      {player && <Composite.add object={player} />}
      <video
        ref={videoRef}
        className="fixed w-px h-px opacity-0 pointer-events-none -z-1"
        aria-hidden
        muted
        playsInline
      />
    </>
  );
}

function MenuArenaDraw({
  titleLine1,
  titleLine2,
  accentColor,
  chainSetRef,
  player,
  escapeQuipsRef,
  chainBreakFxRef,
  headRef,
}: {
  titleLine1: string;
  titleLine2: string;
  accentColor: string;
  chainSetRef: React.RefObject<MenuChainSet | null>;
  player: MatterComposite | undefined;
  escapeQuipsRef: React.MutableRefObject<EscapeQuip[]>;
  chainBreakFxRef: React.MutableRefObject<ChainBreakFx[]>;
  headRef: React.RefObject<Body | undefined>;
}) {
  const render = useRender();
  useRenderEvent(
    "afterRender",
    () => {
      const ctx = render.context;
      if (!ctx) return;
      const now = performance.now();

      drawMenuArenaTitle(
        ctx,
        render,
        { line1: titleLine1, line2: titleLine2, accentColor },
        now,
      );
      drawMenuChains(ctx, render, chainSetRef.current, player, now);

      chainBreakFxRef.current = pruneChainBreakFx(chainBreakFxRef.current ?? [], now);
      drawChainBreakFx(ctx, render, chainBreakFxRef.current, now, accentColor);

      escapeQuipsRef.current = pruneEscapeQuips(escapeQuipsRef.current ?? [], now);
      const head = headRef.current;
      if (head && escapeQuipsRef.current.length > 0) {
        drawEscapeQuips(
          ctx,
          render,
          escapeQuipsRef.current,
          head.position.x,
          head.position.y,
          now,
        );
      }
    },
    [render, titleLine1, titleLine2, accentColor, chainSetRef, player, escapeQuipsRef, chainBreakFxRef, headRef],
  );
  return null;
}
