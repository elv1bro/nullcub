/**
 * Платформенная идентичность сборки.
 * Web → обязательный облачный логин (Supabase).
 * Steam / Electron store → свой ID платформы; веб-OAuth опционален (линк аккаунта).
 */

export type AppPlatform = "web" | "steam" | "electron" | "local";

/** Канонический провайдер аккаунта в облаке (когда появится Steam ticket → `steam`). */
export type IdentityProvider = "google" | "discord" | "email" | "steam" | "local";

export function getAppPlatform(): AppPlatform {
  if (typeof window === "undefined") return "web";
  const w = window as Window & {
    electronAPI?: unknown;
    __RAGDOLL_PLATFORM__?: string;
  };
  // Runtime override (Electron preload / тесты) важнее env сборки.
  const runtime = (w.__RAGDOLL_PLATFORM__ ?? "").toLowerCase().trim();
  if (
    runtime === "steam" ||
    runtime === "electron" ||
    runtime === "local" ||
    runtime === "web"
  ) {
    return runtime;
  }
  const env = (import.meta.env.VITE_PLATFORM ?? "").toLowerCase().trim();
  if (env === "steam" || env === "electron" || env === "local" || env === "web") {
    return env;
  }
  if (typeof w.electronAPI !== "undefined") return "electron";
  return "web";
}

/** На сторах платформа уже «залогинила» игрока — Google/Discord не блокируют старт. */
export function platformSkipsWebAuthGate(platform: AppPlatform = getAppPlatform()): boolean {
  return platform === "steam" || platform === "electron" || platform === "local";
}

/**
 * Заглушка Steam identity (позже: steamworks session ticket → Supabase).
 * Пока всегда null — веб-логин не затрагиваем.
 */
export function getSteamIdentityStub(): { steamId: string } | null {
  if (getAppPlatform() !== "steam") return null;
  const w = window as Window & { __RAGDOLL_STEAM_ID__?: string };
  if (typeof w.__RAGDOLL_STEAM_ID__ === "string" && w.__RAGDOLL_STEAM_ID__) {
    return { steamId: w.__RAGDOLL_STEAM_ID__ };
  }
  return null;
}
