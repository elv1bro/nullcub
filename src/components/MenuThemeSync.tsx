import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useEffect } from "react";

/** Синхронизирует CSS-токены меню с цветами профиля (меню, бой, lab). */
export function MenuThemeSync() {
  const { profile } = usePlayerProfile();

  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty("--menu-accent", profile.colors.main);
    root.style.setProperty("--menu-accent-secondary", profile.colors.secondary);
  }, [profile.colors.main, profile.colors.secondary]);

  return null;
}
