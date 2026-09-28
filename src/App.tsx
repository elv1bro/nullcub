import { AdShortProbe } from "@/ad/AdShortProbe";
import { AudioDirector } from "@/audio/AudioDirector";
import { AuthGate } from "@/components/AuthGate";
import { BootSplash } from "@/components/BootSplash";
import { FpsCounter } from "@/components/FpsCounter";
import { MobileFullscreenGate } from "@/components/MobileFullscreenGate";
import { MenuThemeSync } from "@/components/MenuThemeSync";
import { StrikeLabBootstrap } from "@/components/StrikeLabBootstrap";
import { useActor } from "@xstate/react";
import { Suspense, lazy, useContext, useMemo, useState } from "react";
import { GameContext, GameContextProvider, type States } from "./GameContext";
import { AuthProvider } from "./cloud/AuthContext";
import { PlayerProfileProvider } from "./player/PlayerProfileContext";
import { AchievementsProvider } from "./achievements/AchievementsContext";
import { NetSessionProvider } from "./net/NetSessionContext";
import { WsSessionProvider } from "./net/WsSessionContext";
import { SettingsProvider } from "./settings/SettingsContext";
import { RagdollLoader } from "./components/RagdollLoader";
import { routes } from "./routes";

function isAdProbe(): boolean {
  if (typeof window === "undefined") return false;
  return new URLSearchParams(window.location.search).get("ad") === "probe";
}

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

function bootSkipsSplash(): boolean {
  if (typeof window === "undefined") return true;
  if (new URLSearchParams(window.location.search).has("e2e")) return true;
  if (navigator.webdriver) return true;
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return true;
  return false;
}

function GameShell() {
  return (
    <main className="h-screen">
      <Suspense fallback={<RagdollLoader />}>
        <Router routes={routes} />
      </Suspense>
    </main>
  );
}

/**
 * После входа — заставка (тап → звук → дождь бойцов), затем меню.
 * Логин всегда раньше «запуска» игры.
 */
function SplashThenGame() {
  const [splashDone, setSplashDone] = useState(() => bootSkipsSplash());

  if (!splashDone) {
    return <BootSplash onFinished={() => setSplashDone(true)} />;
  }
  return (
    <>
      {/* После заставки: на телефоне обязательный fullscreen. */}
      <MobileFullscreenGate />
      <GameShell />
    </>
  );
}

function LoginThenBoot() {
  return (
    <AuthGate>
      <SplashThenGame />
    </AuthGate>
  );
}

export default function App() {
  if (isAdProbe()) {
    return <AdShortProbe />;
  }

  return (
    <SettingsProvider>
      <AuthProvider>
        <PlayerProfileProvider>
          <AchievementsProvider>
            <NetSessionProvider>
              <WsSessionProvider>
                <GameContextProvider>
                  <MenuThemeSync />
                  <AudioDirector />
                  <StrikeLabBootstrap />
                  <FpsCounter />
                  <LoginThenBoot />
                </GameContextProvider>
              </WsSessionProvider>
            </NetSessionProvider>
          </AchievementsProvider>
        </PlayerProfileProvider>
      </AuthProvider>
    </SettingsProvider>
  );
}
