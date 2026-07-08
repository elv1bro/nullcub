import type { FaceOverlayEffectId } from "@/face/faceEffects";
import type { MedalId } from "@/lib/achievements/medals";
import { MEDAL_BY_ID } from "@/lib/achievements/medals";
import {
  DEFAULT_AVATAR_FACE_ID,
  isValidAvatarFaceId,
} from "@/face/avatarPresets";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";
import type { FighterColors } from "@/lib/fighterColors";

export interface PlayerProfile {
  name: string;
  colors: FighterColors;
  useCamera: boolean;
  useMicrophone: boolean;
  faceEffect: FaceOverlayEffectId;
  avatarFaceId: string;
  lastBattleAvatarFaceId: string | null;
  lastBattleMedalId: MedalId | null;
}

const STORAGE_KEY = "ragdoll-faces-profile";

export const DEFAULT_PLAYER_PROFILE: PlayerProfile = {
  name: "YOU",
  colors: { main: "#38bdf8", secondary: "#0284c7" },
  useCamera: true,
  useMicrophone: false,
  faceEffect: "none",
  avatarFaceId: DEFAULT_AVATAR_FACE_ID,
  lastBattleAvatarFaceId: null,
  lastBattleMedalId: null,
};

export { COLOR_PRESETS } from "./colorPresets";
export type { FaceOverlayEffectId } from "@/face/faceEffects";

function loadProfile(): PlayerProfile {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_PLAYER_PROFILE;
    const parsed = JSON.parse(raw) as Partial<PlayerProfile>;
    const faceEffect = parsed.faceEffect ?? DEFAULT_PLAYER_PROFILE.faceEffect;
    return {
      name: parsed.name?.trim() || DEFAULT_PLAYER_PROFILE.name,
      colors: {
        main: parsed.colors?.main || DEFAULT_PLAYER_PROFILE.colors.main,
        secondary:
          parsed.colors?.secondary || DEFAULT_PLAYER_PROFILE.colors.secondary,
      },
      useCamera: parsed.useCamera ?? DEFAULT_PLAYER_PROFILE.useCamera,
      useMicrophone:
        parsed.useMicrophone ?? DEFAULT_PLAYER_PROFILE.useMicrophone,
      faceEffect:
        faceEffect === "fire_eyes" ||
        faceEffect === "laser_eyes" ||
        faceEffect === "glitch" ||
        faceEffect === "halo" ||
        faceEffect === "demon" ||
        faceEffect === "none"
          ? faceEffect
          : DEFAULT_PLAYER_PROFILE.faceEffect,
      avatarFaceId: isValidAvatarFaceId(parsed.avatarFaceId ?? "")
        ? (parsed.avatarFaceId as string)
        : DEFAULT_AVATAR_FACE_ID,
      lastBattleAvatarFaceId: isValidAvatarFaceId(
        parsed.lastBattleAvatarFaceId ?? "",
      )
        ? (parsed.lastBattleAvatarFaceId as string)
        : null,
      lastBattleMedalId:
        parsed.lastBattleMedalId &&
        parsed.lastBattleMedalId in MEDAL_BY_ID
          ? (parsed.lastBattleMedalId as MedalId)
          : null,
    };
  } catch {
    return DEFAULT_PLAYER_PROFILE;
  }
}

function saveProfile(profile: PlayerProfile): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(profile));
}

interface PlayerProfileContextValue {
  profile: PlayerProfile;
  setName: (name: string) => void;
  setColors: (colors: FighterColors) => void;
  setMainColor: (main: string) => void;
  setSecondaryColor: (secondary: string) => void;
  setUseCamera: (value: boolean) => void;
  setUseMicrophone: (value: boolean) => void;
  setFaceEffect: (effect: FaceOverlayEffectId) => void;
  setAvatarFaceId: (id: string) => void;
  setLastBattleSnapshot: (snapshot: {
    avatarFaceId?: string | null;
    medalId?: MedalId | null;
  }) => void;
}

const PlayerProfileContext = createContext<PlayerProfileContextValue | null>(
  null,
);

export function PlayerProfileProvider({ children }: PropsWithChildren) {
  const [profile, setProfile] = useState<PlayerProfile>(loadProfile);

  const update = useCallback((patch: (prev: PlayerProfile) => PlayerProfile) => {
    setProfile((prev) => {
      const next = patch(prev);
      saveProfile(next);
      return next;
    });
  }, []);

  const value = useMemo<PlayerProfileContextValue>(
    () => ({
      profile,
      setName: (name) =>
        update((prev) => ({
          ...prev,
          name: name.slice(0, 16).trim() || DEFAULT_PLAYER_PROFILE.name,
        })),
      setColors: (colors) => update((prev) => ({ ...prev, colors })),
      setMainColor: (main) =>
        update((prev) => ({ ...prev, colors: { ...prev.colors, main } })),
      setSecondaryColor: (secondary) =>
        update((prev) => ({ ...prev, colors: { ...prev.colors, secondary } })),
      setUseCamera: (useCamera) => update((prev) => ({ ...prev, useCamera })),
      setUseMicrophone: (useMicrophone) =>
        update((prev) => ({ ...prev, useMicrophone })),
      setFaceEffect: (faceEffect) => update((prev) => ({ ...prev, faceEffect })),
      setAvatarFaceId: (avatarFaceId) =>
        update((prev) =>
          isValidAvatarFaceId(avatarFaceId)
            ? { ...prev, avatarFaceId }
            : prev,
        ),
      setLastBattleSnapshot: (snapshot) =>
        update((prev) => ({
          ...prev,
          ...(snapshot.avatarFaceId !== undefined
            ? {
                lastBattleAvatarFaceId: isValidAvatarFaceId(
                  snapshot.avatarFaceId ?? "",
                )
                  ? snapshot.avatarFaceId
                  : null,
              }
            : {}),
          ...(snapshot.medalId !== undefined
            ? { lastBattleMedalId: snapshot.medalId }
            : {}),
        })),
    }),
    [profile, update],
  );

  return (
    <PlayerProfileContext.Provider value={value}>
      {children}
    </PlayerProfileContext.Provider>
  );
}

export function usePlayerProfile(): PlayerProfileContextValue {
  const ctx = useContext(PlayerProfileContext);
  if (!ctx) {
    throw new Error("usePlayerProfile must be used within PlayerProfileProvider");
  }
  return ctx;
}
