import { botEmotion } from "@/face/emotions";
import { useFaceTracker } from "@/face/tracker";
import { useBattleOverlay } from "@/lib/useBattleOverlay";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";
import type { Body } from "matter-js";
import { useMemo, useRef } from "react";
import type { FighterRuntime } from "./types";

/**
 * Лица/HUD для roster-боёв (пати vs боты, 4FFA): head в Matter скрыт —
 * рисуем через afterRender, иначе бойцы выглядят безголовыми.
 */
export function RosterBattleOverlay({
  fighters,
}: {
  fighters: FighterRuntime[];
}) {
  const { profile } = usePlayerProfile();
  const { settings } = useSettings();
  const { ready, error, videoRef, cropRef } = useFaceTracker({
    enabled: profile.useCamera,
    audio: false,
    tracking: false,
  });
  const webcamActive = profile.useCamera && ready && !error;

  const local =
    fighters.find((f) => f.isLocalHuman && f.controller === "keyboard") ??
    fighters.find((f) => f.isLocalHuman) ??
    fighters[0];
  const boss =
    fighters.find((f) => f.team !== (local?.team ?? 0)) ??
    fighters.find((f) => !f.isLocalHuman) ??
    null;

  const playerHeadRef = useRef<Body | undefined>(undefined);
  const opponentHeadRef = useRef<Body | undefined>(undefined);
  const extraHeadRefs = useRef<Record<string, { current: Body | undefined }>>(
    {},
  );

  playerHeadRef.current = local?.head;
  opponentHeadRef.current = boss?.head;

  const extras = useMemo(() => {
    const skip = new Set(
      [local?.id, boss?.id].filter(Boolean) as string[],
    );
    return fighters
      .filter((f) => !skip.has(f.id))
      .map((f) => {
        if (!extraHeadRefs.current[f.id]) {
          extraHeadRefs.current[f.id] = { current: undefined };
        }
        const headRef = extraHeadRefs.current[f.id]!;
        headRef.current = f.head;
        return {
          head: headRef,
          hud: {
            name: f.name,
            hearts: f.hp,
            maxHearts: f.maxHp,
            colors: f.colors,
            side: (f.team === (local?.team ?? 0) ? "left" : "right") as
              | "left"
              | "right",
          },
          face: botEmotion(f.hp, f.maxHp, false),
          colors: f.colors,
          composite: f.composite,
        };
      });
  }, [fighters, local?.id, local?.team, boss?.id]);

  const playerHud = local
    ? {
        name: local.name,
        hearts: local.hp,
        maxHearts: local.maxHp,
        colors: local.colors,
        side: "left" as const,
      }
    : null;
  const opponentHud = boss
    ? {
        name: boss.name,
        hearts: boss.hp,
        maxHearts: boss.maxHp,
        colors: boss.colors,
        side: "right" as const,
      }
    : null;

  const opponentFace = boss
    ? botEmotion(boss.hp, boss.maxHp, false)
    : null;

  useBattleOverlay(
    {
      playerHead: playerHeadRef,
      opponentHead: opponentHeadRef,
      ...(local ? { playerComposite: local.composite } : {}),
      ...(boss ? { opponentComposite: boss.composite } : {}),
      playerVideo: videoRef,
      playerCrop: cropRef,
      opponentFace,
      playerPain: false,
      webcamActive,
      ...(profile.faceEffect ? { faceEffect: profile.faceEffect } : {}),
      ...(webcamActive
        ? {}
        : profile.avatarFaceId
          ? { avatarFaceId: profile.avatarFaceId }
          : {}),
      playerHp: local?.hp,
      playerMaxHp: local?.maxHp,
      playerHud,
      opponentHud,
      opponentColors: boss?.colors,
      playerColors: local?.colors ?? profile.colors,
      extraFighters: extras,
      language: settings.language,
    },
    [
      fighters,
      extras,
      playerHud,
      opponentHud,
      opponentFace,
      webcamActive,
      profile.faceEffect,
      profile.avatarFaceId,
      profile.colors,
      settings.language,
      local?.composite,
      boss?.composite,
    ],
  );

  // Нужен DOM-узел для getUserMedia; без него webcam-ветка не стартует.
  return (
    <video
      ref={videoRef}
      className="hidden"
      playsInline
      muted
      aria-hidden
    />
  );
}
