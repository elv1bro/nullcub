import { FixedViewport } from "@/components/FixedViewport";
import { Renderer } from "@/components/Renderer";
import { formatHeartCount } from "@/lib/fighterColors";
import { useSettings } from "@/settings/SettingsContext";
import { MAX_HP } from "@/lib/combat";
import { isDebugMode } from "@/lib/debugMode";
import { applyPlayerColors } from "@/lib/paintStickman";
import { useFaceTracker } from "@/face/tracker";
import { useBattleOverlay } from "@/lib/useBattleOverlay";
import { moveBody } from "@/lib/moveBody";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { createStickman } from "@/utils/createStickman";
import { Composite, SurroundingWalls } from "@1.framework/matter4react";
import Matter, { Body, Vector, type IEventTimestamped } from "matter-js";
import { useCallback, useEffect, useRef, useState } from "react";
import { PlayerMovementInput } from "@/input/PlayerMovementInput";

const ARENA = 520;
const PLAYER_MOVE_SPEED = 18;

interface SceneProps {
  width: number;
  height: number;
  onReady: () => void;
  onWebcamStatus?: (active: boolean, failed: boolean) => void;
}

function MenuPreviewScene({ width, height, onReady, onWebcamStatus }: SceneProps) {
  const { profile } = usePlayerProfile();
  const { ready, error, videoRef, cropRef } = useFaceTracker(true);
  const webcamActive = ready && !error;

  const [player, setPlayer] = useState<Matter.Composite>();
  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const playerHeadRef = useRef<Body>();

  useEffect(() => {
    const p = createStickman(ARENA * 0.5, ARENA * 0.52, {
      render: { fillStyle: profile.colors.main },
    });
    applyPlayerColors(p, profile.colors.main, profile.colors.secondary);

    const pHead = p.bodies.at(0);
    if (pHead) pHead.render.visible = false;

    playerHeadRef.current = pHead;
    setPlayer(p);
    setProtagonists([...p.bodies]);

    if (pHead) Matter.Body.setVelocity(pHead, { x: 1.5, y: -3 });

    onReady();
  }, [profile.colors.main, profile.colors.secondary, onReady]);

  useEffect(() => {
    onWebcamStatus?.(webcamActive, !!error);
  }, [webcamActive, error, onWebcamStatus]);

  useEffect(() => {
    if (!player) return;
    applyPlayerColors(player, profile.colors.main, profile.colors.secondary);
  }, [player, profile.colors.main, profile.colors.secondary]);

  const onMove = useCallback(
    (event: IEventTimestamped<Matter.Engine>, direction: Vector) => {
      if (!playerHeadRef.current) return;
      moveBody(playerHeadRef.current)(event, direction, PLAYER_MOVE_SPEED);
    },
    [],
  );

  useBattleOverlay(
    {
      playerHead: playerHeadRef,
      playerComposite: player,
      playerVideo: videoRef,
      playerCrop: cropRef,
      playerPain: false,
      webcamActive,
      playerColors: profile.colors,
      playerHud: null,
    },
    [
      webcamActive,
      player,
      profile.colors.main,
      profile.colors.secondary,
    ],
  );

  const bounds = Matter.Bounds.create([
    { x: 0, y: 0 },
    { x: ARENA, y: ARENA },
  ]);

  return (
    <>
      <FixedViewport
        width={width}
        height={height}
        padding={100}
        protagonists={protagonists}
      />
      <PlayerMovementInput map="menu" event="move" call={onMove} />
      <SurroundingWalls
        thick={ARENA}
        bounds={bounds}
        options={{ render: { fillStyle: "#1a1a24" } }}
      />
      {player && <Composite.add object={player} />}
      {/* Скрытый источник кадров для лица на голове: без него трекер не стартует */}
      <video
        ref={videoRef}
        className="fixed w-px h-px opacity-0 pointer-events-none -z-1"
        muted
        playsInline
        aria-hidden
      />
    </>
  );
}

export function MenuPreviewArena() {
  const { profile } = usePlayerProfile();
  const { t } = useSettings();
  const frameRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 360, h: 400 });
  const [loaded, setLoaded] = useState(false);
  const [webcamFailed, setWebcamFailed] = useState(false);

  const onReady = useCallback(() => setLoaded(true), []);
  const onWebcamStatus = useCallback((_active: boolean, failed: boolean) => {
    setWebcamFailed(failed);
  }, []);

  useEffect(() => {
    const el = frameRef.current;
    if (!el) return;
    const measure = () => {
      const { width, height } = el.getBoundingClientRect();
      if (width > 0 && height > 0) {
        setSize({ w: Math.floor(width), h: Math.floor(height) });
      }
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div className="w-full">
      <div ref={frameRef} className="menu-hero-preview-frame">
        {!loaded && <div className="menu-preview-skeleton" aria-hidden />}
        {size.w > 0 && size.h > 0 && (
          <Renderer
            render={{
              options: {
                width: size.w,
                height: size.h,
                background: "#0e0e16",
                wireframes: false,
              },
            }}
          >
            <MenuPreviewScene
              width={size.w}
              height={size.h}
              onReady={onReady}
              onWebcamStatus={onWebcamStatus}
            />
          </Renderer>
        )}
      </div>

      <div className="menu-preview-meta">
        <p
          className="menu-preview-name"
          style={{
            color: profile.colors.main,
            textShadow: `0 0 24px color-mix(in srgb, ${profile.colors.main} 40%, transparent)`,
          }}
        >
          {profile.name}
        </p>
        <p className="menu-preview-hearts" style={{ color: profile.colors.main }}>
          {formatHeartCount(MAX_HP)}
        </p>
        <p className="menu-preview-hint font-ui">{t.menu.previewHint}</p>
        {webcamFailed && (
          <p className="menu-preview-hint text-amber-400/80">{t.menu.webcamOff}</p>
        )}
      </div>

      {isDebugMode() && (
        <p className="text-xs text-yellow-300/70 font-mono text-center mt-1">
          debug
        </p>
      )}
    </div>
  );
}
