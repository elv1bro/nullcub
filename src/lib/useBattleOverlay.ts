import { useRender, useRenderEvent } from "@1.framework/matter4react";
import Matter from "matter-js";
import {
  type DependencyList,
  type MutableRefObject,
  type RefObject,
} from "react";
import {
  drawFaceOnHead,
  drawHeadFrameOnHead,
  drawPlaceholderHead,
  drawWebcamOnHead,
} from "@/face/drawFace";
import { avatarBattleEmotion } from "@/face/avatarEmotion";
import type { EmotionId } from "@/face/emotions";
import { getAvatarFacePreset } from "@/face/avatarPresets";
import { drawAvatarOnHead } from "@/face/drawAvatarFace";
import type { FaceCropRect } from "@/face/faceCrop";
import type { FaceState } from "@/face/emotions";
import { isDebugMode } from "@/lib/debugMode";
import type { FaceOverlayEffectId } from "@/face/faceEffects";
import { PLAYER_COLORS, OPPONENT_COLORS, type FighterColors } from "@/lib/fighterColors";
import { drawHitBursts, pruneBursts, type HitBurst } from "@/lib/hitVfx";
import { decayPopupPulse, prunePopups, type HitPopup } from "@/lib/hitPopups";
import { pruneBanter, type BanterQuip } from "@/lib/banterQuips";
import {
  drawComboAndAnnouncer,
  drawFinisherVignette,
  drawGroundShockwaves,
  drawScreenFlash,
  pruneHitEffectStore,
  type HitEffectStore,
} from "@/lib/hitEffects";
import { drawBanterQuips } from "@/render/drawBanterQuips";
import { repaintRagdollBodies } from "@/render/repaintRagdollBodies";
import { drawBodySpeeds, drawHitDebug } from "@/render/drawDebugOverlay";
import { drawFighterHud, type FighterHudInfo } from "@/render/drawFighterHud";
import { drawHitPopup } from "@/render/drawHitPopup";
import { drawLimbTipInlays } from "@/render/drawLimbTipInlay";
import { drawGrabLines } from "@/render/drawGrabLines";
import type { GrabVisualLine } from "@/lib/grab/types";
import {
  hasDueCaptures,
  processPendingCaptures,
  type BattleMomentsStore,
} from "@/lib/battleMoments";

interface OverlayOptions {
  playerHead: RefObject<Matter.Body | undefined>;
  opponentHead?: RefObject<Matter.Body | undefined>;
  playerComposite?: Matter.Composite;
  opponentComposite?: Matter.Composite;
  playerVideo: RefObject<HTMLVideoElement | null>;
  playerCrop: RefObject<FaceCropRect | null>;
  opponentFace?: FaceState | null;
  opponentVideo?: RefObject<HTMLVideoElement | null>;
  opponentCrop?: RefObject<FaceCropRect | null>;
  opponentWebcamActive?: boolean;
  playerPain: boolean;
  webcamActive: boolean;
  playerHud?: FighterHudInfo | null;
  opponentHud?: FighterHudInfo | null;
  /** Цвета игрока для обводки лица и кончиков, если HUD не передан (меню). */
  playerColors?: FighterColors;
  opponentColors?: FighterColors;
  faceEffect?: FaceOverlayEffectId;
  avatarFaceId?: string;
  /** HP игрока для эмоций аватара без вебки. */
  playerHp?: number;
  playerMaxHp?: number;
  playerLastHit?: "player" | "opponent" | null;
  playerAvatarEmotion?: EmotionId;
  opponentAvatarFaceId?: string;
  opponentHp?: number;
  opponentMaxHp?: number;
  opponentPain?: boolean;
  opponentLastHit?: "player" | "opponent" | null;
  opponentAvatarEmotion?: EmotionId;
  popupsRef?: MutableRefObject<HitPopup[]>;
  burstsRef?: MutableRefObject<HitBurst[]>;
  banterRef?: MutableRefObject<BanterQuip[]>;
  hitEffectsStore?: RefObject<HitEffectStore | null>;
  language?: "en" | "ru";
  lastHitDebug?: RefObject<string | null>;
  battleMomentsStore?: RefObject<BattleMomentsStore | null>;
  onMomentCaptured?: () => void;
  grabLinesRef?: RefObject<GrabVisualLine[]>;
}

export function useBattleOverlay(
  opts: OverlayOptions,
  deps: DependencyList,
): void {
  const render = useRender();
  const debug = isDebugMode();

  useRenderEvent(
    "afterRender",
    () => {
      const ctx = render.context;
      if (!ctx) return;

      const now = performance.now();
      const fxStore = opts.hitEffectsStore?.current;
      const momentsStore = opts.battleMomentsStore?.current;
      const captureDue = momentsStore
        ? hasDueCaptures(momentsStore, now)
        : false;

      if (fxStore) {
        pruneHitEffectStore(fxStore, now);
        drawGroundShockwaves(ctx, render, fxStore, now);
        drawScreenFlash(ctx, render, fxStore, now);
        drawFinisherVignette(ctx, render, fxStore, now);
        drawComboAndAnnouncer(
          ctx,
          render,
          fxStore,
          opts.language ?? "ru",
          now,
          opts.playerColors ?? opts.playerHud?.colors ?? PLAYER_COLORS,
          opts.opponentColors ?? opts.opponentHud?.colors ?? OPPONENT_COLORS,
        );
      }

      if (opts.banterRef?.current?.length) {
        opts.banterRef.current = pruneBanter(opts.banterRef.current, now);
        drawBanterQuips(ctx, render, opts.banterRef.current, now);
        const ragdollBodies = [
          ...(opts.playerComposite?.bodies ?? []),
          ...(opts.opponentComposite?.bodies ?? []),
        ];
        repaintRagdollBodies(render, ctx, ragdollBodies);
      }

      if (opts.burstsRef?.current) {
        opts.burstsRef.current = pruneBursts(opts.burstsRef.current, now);
        drawHitBursts(ctx, render, opts.burstsRef.current, now);
      }

      if (opts.popupsRef?.current) {
        decayPopupPulse(opts.popupsRef.current);
        opts.popupsRef.current = prunePopups(opts.popupsRef.current, now);
        for (const popup of opts.popupsRef.current) {
          drawHitPopup(ctx, render, popup, now);
        }
      }

      if (opts.grabLinesRef?.current?.length) {
        drawGrabLines(ctx, render, opts.grabLinesRef.current);
      }

      if (opts.playerComposite) {
        const tipColor =
          opts.playerHud?.colors.secondary ??
          opts.playerColors?.secondary ??
          "#888888";
        drawLimbTipInlays(ctx, render, opts.playerComposite, tipColor);
      }
      if (opts.opponentComposite) {
        const tipColor =
          opts.opponentHud?.colors.secondary ??
          opts.opponentColors?.secondary ??
          "#666666";
        drawLimbTipInlays(ctx, render, opts.opponentComposite, tipColor);
      }

      const playerFrame =
        opts.playerHud?.colors.main ?? opts.playerColors?.main ?? "#333333";

      const video = opts.playerVideo.current;
      if (opts.playerHead.current) {
        const canDrawWebcam =
          opts.webcamActive &&
          video &&
          video.readyState >= 2 &&
          video.videoWidth > 0;

        if (canDrawWebcam) {
          drawWebcamOnHead(ctx, render, opts.playerHead.current, video, {
            painFlash: opts.playerPain,
            crop: opts.playerCrop.current,
            faceEffect: opts.faceEffect,
            now,
          });
        } else if (opts.avatarFaceId) {
          const avatarEmotion =
            opts.playerAvatarEmotion ??
            (opts.playerHp != null && opts.playerMaxHp != null
              ? avatarBattleEmotion(
                  opts.playerHp,
                  opts.playerMaxHp,
                  opts.playerPain,
                  opts.playerLastHit ?? null,
                )
              : "neutral");
          drawAvatarOnHead(
            ctx,
            render,
            opts.playerHead.current,
            getAvatarFacePreset(opts.avatarFaceId),
            {
              faceEffect: opts.faceEffect,
              now,
              painFlash: opts.playerPain,
              emotion: avatarEmotion,
            },
          );
        } else {
          drawPlaceholderHead(
            ctx,
            render,
            opts.playerHead.current,
            playerFrame,
            {
              faceEffect: opts.faceEffect,
              now,
            },
          );
          drawHeadFrameOnHead(
            ctx,
            render,
            opts.playerHead.current,
            playerFrame,
          );
        }
        if (opts.playerHud) {
          drawFighterHud(ctx, render, opts.playerHead.current, opts.playerHud);
        }
      }

      if (opts.opponentHead?.current) {
        const opponentFrame = opts.opponentHud?.colors.main ?? "#333333";
        const oppVideo = opts.opponentVideo?.current;
        const canDrawOppWebcam =
          opts.opponentWebcamActive &&
          oppVideo &&
          oppVideo.readyState >= 2 &&
          oppVideo.videoWidth > 0;

        if (canDrawOppWebcam) {
          drawWebcamOnHead(
            ctx,
            render,
            opts.opponentHead.current,
            oppVideo,
            {
              crop: opts.opponentCrop?.current ?? null,
              frameColor: opponentFrame,
              now,
            },
          );
        } else if (opts.opponentAvatarFaceId) {
          const oppEmotion =
            opts.opponentAvatarEmotion ??
            (opts.opponentHp != null && opts.opponentMaxHp != null
              ? avatarBattleEmotion(
                  opts.opponentHp,
                  opts.opponentMaxHp,
                  opts.opponentPain ?? false,
                  opts.opponentLastHit === "player"
                    ? "opponent"
                    : opts.opponentLastHit === "opponent"
                      ? "player"
                      : null,
                )
              : "neutral");
          drawAvatarOnHead(
            ctx,
            render,
            opts.opponentHead.current,
            getAvatarFacePreset(opts.opponentAvatarFaceId),
            {
              now,
              painFlash: opts.opponentPain ?? false,
              emotion: oppEmotion,
            },
          );
        } else if (opts.opponentFace) {
          drawFaceOnHead(
            ctx,
            render,
            opts.opponentHead.current,
            opts.opponentFace,
            opponentFrame,
          );
          drawHeadFrameOnHead(
            ctx,
            render,
            opts.opponentHead.current,
            opponentFrame,
          );
        } else {
          drawPlaceholderHead(
            ctx,
            render,
            opts.opponentHead.current,
            opponentFrame,
            { now },
          );
          drawHeadFrameOnHead(
            ctx,
            render,
            opts.opponentHead.current,
            opponentFrame,
          );
        }
        if (opts.opponentHud) {
          drawFighterHud(ctx, render, opts.opponentHead.current, opts.opponentHud);
        }
      }

      if (debug) {
        if (opts.playerComposite) {
          drawBodySpeeds(
            ctx,
            render,
            opts.playerComposite,
            opts.playerHud?.name ?? "P1",
            "#7df9ff",
            0,
          );
        }
        if (opts.opponentComposite) {
          drawBodySpeeds(
            ctx,
            render,
            opts.opponentComposite,
            opts.opponentHud?.name ?? "P2",
            "#f87171",
            14,
          );
        }
        const hitText = opts.lastHitDebug?.current;
        if (hitText && opts.playerHead.current) {
          drawHitDebug(
            ctx,
            render,
            opts.playerHead.current.position.x,
            opts.playerHead.current.position.y - 40,
            hitText,
          );
        }
      }

      if (
        momentsStore &&
        captureDue &&
        processPendingCaptures(momentsStore, render.canvas, now)
      ) {
        opts.onMomentCaptured?.();
      }
    },
    [render, debug, ...deps],
  );
}
