import { AudioDirector } from "@/audio/AudioDirector";
import { MenuThemeSync } from "@/components/MenuThemeSync";
import { StrikeLabBootstrap } from "@/components/StrikeLabBootstrap";
import { useActor } from "@xstate/react";
import { Suspense, lazy, useContext, useMemo } from "react";
import { GameContext, GameContextProvider, type States } from "./GameContext";
import { PlayerProfileProvider } from "./player/PlayerProfileContext";
import { AchievementsProvider } from "./achievements/AchievementsContext";
import { NetSessionProvider } from "./net/NetSessionContext";
import { WsSessionProvider } from "./net/WsSessionContext";
import { SettingsProvider } from "./settings/SettingsContext";
import { Loading } from "./components/Loading";
import { routes } from "./routes";

function Router({ routes }: { routes: Map<States, ReturnType<typeof lazy>> }) {
  const { gameM } = useContext(GameContext);
  const [gameA] = useActor(gameM);

  const match = useMemo(
    () => Array.from(routes).find(([state]) => gameA.matches(state)),
    [gameA],
  );

  if (!match) {
    return <>{String(gameA.value)} not found</>;
  }

  const [, Component] = match;
  return <Component />;
}

const LoadingScreen = () => (
  <div className="vstack h-100% items-center justify-center">
    <Loading />
  </div>
);

export default function App() {
  return (
    <SettingsProvider>
      <PlayerProfileProvider>
        <AchievementsProvider>
        <NetSessionProvider>
        <WsSessionProvider>
        <GameContextProvider>
          <MenuThemeSync />
          <AudioDirector />
          <StrikeLabBootstrap />
          <main className="h-screen">
            <Suspense fallback={<LoadingScreen />}>
              <Router routes={routes} />
            </Suspense>
          </main>
        </GameContextProvider>
        </WsSessionProvider>
        </NetSessionProvider>
        </AchievementsProvider>
      </PlayerProfileProvider>
    </SettingsProvider>
  );
}
