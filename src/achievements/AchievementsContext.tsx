import { CLOUD_SYNC_EVENT } from "@/cloud/cloudEvents";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";
import {
  loadPlayerStats,
  type PlayerStats,
} from "@/lib/achievements/store";

interface AchievementsContextValue {
  stats: PlayerStats;
  refreshStats: () => void;
}

const AchievementsContext = createContext<AchievementsContextValue | null>(
  null,
);

export function AchievementsProvider({ children }: PropsWithChildren) {
  const [stats, setStats] = useState<PlayerStats>(loadPlayerStats);

  const refreshStats = useCallback(() => {
    setStats(loadPlayerStats());
  }, []);

  useEffect(() => {
    const onSync = () => refreshStats();
    window.addEventListener(CLOUD_SYNC_EVENT, onSync);
    return () => window.removeEventListener(CLOUD_SYNC_EVENT, onSync);
  }, [refreshStats]);

  const value = useMemo(
    () => ({ stats, refreshStats }),
    [stats, refreshStats],
  );

  return (
    <AchievementsContext.Provider value={value}>
      {children}
    </AchievementsContext.Provider>
  );
}

export function useAchievements(): AchievementsContextValue {
  const ctx = useContext(AchievementsContext);
  if (!ctx) {
    throw new Error("useAchievements must be used within AchievementsProvider");
  }
  return ctx;
}
