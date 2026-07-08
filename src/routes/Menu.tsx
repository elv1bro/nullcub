import { GameContext } from "@/GameContext";
import {
  BOUNCER_CHAPTERS,
  pickL10n,
  type BouncerChapterId,
} from "@/campaign/bouncer";
import { getMaxUnlockedOrder, isChapterUnlocked } from "@/campaign/progress";
import { AchievementsPanel } from "@/components/AchievementsPanel";
import { CustomizePanel } from "@/components/CustomizePanel";
import { ControlsPanel } from "@/components/ControlsPanel";
import { OptionsPanel } from "@/components/OptionsPanel";
import { MenuArena } from "@/components/menu/MenuArena";
import type { MenuPlayPhase } from "@/components/menu/MenuArenaScene";
import { MenuArenaCursor } from "@/components/menu/MenuArenaCursor";
import { MenuBreadcrumb } from "@/components/menu/MenuBreadcrumb";
import { MenuFooter } from "@/components/menu/MenuFooter";
import { MenuCharacterCard } from "@/components/menu/MenuCharacterCard";
import { MenuNav } from "@/components/menu/MenuNav";
import { MenuBackBar } from "@/components/menu/MenuSlidePanel";
import { WsDuelPanel } from "@/components/menu/WsDuelPanel";
import { playMenuSound } from "@/audio";
import { setBattleDedicated, setBattleQuick } from "@/lib/battleConfig";
import { e2eMatches, e2eOk, e2eSetPhase } from "@/dev/e2eHarness";
import { getRoomIdFromHash } from "@/net/room";
import { useNetSession } from "@/net/NetSessionContext";
import { mapRoleToDedicated, useWsSession } from "@/net/WsSessionContext";
import { parseDuelHash } from "@/net/wsClient";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { applyTeamBattleConfig } from "@/team/teamSlots";
import { setBattleConfig } from "@/lib/battleConfig";
import { useSettings, useTranslation } from "@/settings/SettingsContext";
import { useActor } from "@xstate/react";
import { useContext, useCallback, useEffect, useRef, useState } from "react";
import { useKeyPressEvent } from "react-use";

type MenuScreen =
  | "home"
  | "customize"
  | "achievements"
  | "options"
  | "controls"
  | "playPick"
  | "playScope"
  | "campaignPick"
  | "campaignBouncer"
  | "campaignChapter";

export default Menu;

export function Menu() {
  const { sendN, gameM } = useContext(GameContext);
  const [gameA] = useActor(gameM);
  const t = useTranslation();
  const { settings } = useSettings();
  const { guestStartSignal, clearGuestStartSignal, roomId: netRoomId } = useNetSession();
  const ws = useWsSession();
  const { profile } = usePlayerProfile();
  const lang = settings.language;
  const [screen, setScreen] = useState<MenuScreen>("home");
  const [playPhase, setPlayPhase] = useState<MenuPlayPhase>("idle");
  const [chainsBroken, setChainsBroken] = useState(0);
  const [playRunId, setPlayRunId] = useState(0);
  const [selectedChapterId, setSelectedChapterId] = useState<BouncerChapterId | null>(
    null,
  );
  const [, setUnlockedOrder] = useState(() => getMaxUnlockedOrder());
  const resumeScreenRef = useRef<MenuScreen>("playScope");
  const wasBattleRef = useRef(false);
  const deepLinkBootstrappedRef = useRef(false);

  const refreshProgress = useCallback(() => {
    setUnlockedOrder(getMaxUnlockedOrder());
  }, []);

  useEffect(() => {
    if (deepLinkBootstrappedRef.current) return;
    deepLinkBootstrappedRef.current = true;

    const params = new URLSearchParams(window.location.search);
    const devHub = params.get("devHub");
    const devRoom = params.get("room");
    if (devHub && devRoom) {
      const wsPort = params.get("wsPort") ?? "8787";
      const server = params.get("server") ?? `ws://127.0.0.1:${wsPort}`;
      const joinName = params.get("joinName") ?? profile.name;
      setChainsBroken(2);
      setPlayPhase("soaring");
      setScreen("playScope");
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      if (devHub === "host") {
        ws.connectToRoom(joinName, devRoom, "player", server);
      } else if (devHub === "guest") {
        ws.connectToRoom(joinName, devRoom, "opponent", server);
      }
      params.delete("devHub");
      params.delete("room");
      params.delete("wsPort");
      params.delete("server");
      params.delete("joinName");
      const q = params.toString();
      window.history.replaceState(null, "", q ? `?${q}` : window.location.pathname);
      return;
    }

    const duel = parseDuelHash();
    if (duel) {
      setChainsBroken(2);
      setPlayPhase("soaring");
      setScreen("playScope");
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      ws.joinByCode(duel.code, profile.name);
      // Снимаем hash, иначе BACK → Menu remount снова join’ит.
      window.history.replaceState(
        null,
        "",
        `${window.location.pathname}${window.location.search}`,
      );
      return;
    }
    const roomId = getRoomIdFromHash();
    if (!roomId) return;
    setChainsBroken(2);
    setPlayPhase("soaring");
    setScreen("playScope");
    sendN("PLAY")();
    sendN("QUICK_BATTLE")();
  }, [sendN, ws, profile.name, ws.connectToRoom]);

  useEffect(() => {
    if (ws.battleStartSignal === 0) return;
    if (!ws.wsUrl || !ws.roomId || !ws.role) return;
    setBattleDedicated(ws.wsUrl, ws.roomId, mapRoleToDedicated(ws.role));
    sendN("START_BATTLE")();
    ws.clearBattleStartSignal();
  }, [ws.battleStartSignal, ws.wsUrl, ws.roomId, ws.role, ws.clearBattleStartSignal, sendN]);

  useEffect(() => {
    if (e2eMatches("menu")) {
      e2eSetPhase("running");
      const t = setTimeout(() => e2eOk({ screen: "home" }), 800);
      return () => clearTimeout(t);
    }
    if (e2eMatches("quick")) {
      e2eSetPhase("running");
      setBattleQuick();
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      sendN("START_BATTLE")();
    }
    if (e2eMatches("workshop")) {
      e2eSetPhase("running");
      sendN("WORKSHOP")();
    }
    return undefined;
  }, [sendN]);

  useEffect(() => {
    if (guestStartSignal === 0) return;
    // P2P guest auto-start — только при явном VITE_ENABLE_P2P.
    if (import.meta.env.VITE_ENABLE_P2P !== "1" && import.meta.env.VITE_ENABLE_P2P !== "true") {
      clearGuestStartSignal();
      return;
    }
    const roomId = netRoomId ?? getRoomIdFromHash();
    if (!roomId) return;
    applyTeamBattleConfig({
      slots: [],
      remoteCount: 1,
      localHumanCount: 1,
      roomId,
      isHost: false,
    });
    sendN("PLAY")();
    sendN("QUICK_BATTLE")();
    sendN("START_BATTLE")();
    clearGuestStartSignal();
  }, [guestStartSignal, netRoomId, sendN, clearGuestStartSignal]);

  useEffect(() => {
    if (gameA.matches("battle")) {
      wasBattleRef.current = true;
    }
    if (gameA.matches("idle") && wasBattleRef.current) {
      wasBattleRef.current = false;
      setPlayRunId((n) => n + 1);
      const resume = resumeScreenRef.current;
      if (resume === "playScope") {
        setChainsBroken(2);
        setPlayPhase("soaring");
      } else {
        setChainsBroken(0);
        setPlayPhase("idle");
      }
      setScreen(resume);
      refreshProgress();
    }
  }, [gameA, refreshProgress]);

  const advanceToSoaring = useCallback(() => {
    if (playPhase === "partial") {
      setChainsBroken(2);
      setPlayPhase("soaring");
    }
  }, [playPhase]);

  const go = useCallback(
    (next: "customize" | "achievements" | "options" | "controls") => {
      playMenuSound("panel");
      setScreen(next);
    },
    [],
  );

  const goBack = useCallback(() => {
    playMenuSound("click");
    setScreen((prev) => {
      switch (prev) {
        case "playScope":
        case "campaignChapter":
          return "campaignBouncer";
        case "campaignBouncer":
          return "campaignPick";
        case "campaignPick":
          return "playPick";
        case "playPick":
          setChainsBroken(0);
          setPlayPhase("idle");
          return "home";
        default:
          return "home";
      }
    });
  }, []);

  const goHome = useCallback(() => {
    playMenuSound("click");
    setChainsBroken(0);
    setPlayPhase("idle");
    setPlayRunId((n) => n + 1);
    setScreen("home");
  }, []);

  const startChapterBattle = useCallback(
    (chapterId: BouncerChapterId) => {
      playMenuSound("play");
      resumeScreenRef.current = "campaignChapter";
      setBattleConfig({ kind: "campaign", chapterId });
      sendN("PLAY")();
      sendN("CAMPAIGN")();
      sendN("LOCAL_CAMPAIGN")();
      sendN("START_BATTLE")();
    },
    [sendN],
  );

  const openWorkshop = useCallback(() => {
    playMenuSound("panel");
    sendN("WORKSHOP")();
  }, [sendN]);

  useKeyPressEvent("Escape", () => {
    if (screen === "home") return;
    if (screen === "customize" || screen === "achievements" || screen === "options" || screen === "controls") {
      goHome();
    } else {
      goBack();
    }
  });

  const handlePlay = useCallback(() => {
    if (playPhase !== "idle") return;
    playMenuSound("play");
    setChainsBroken(1);
    setPlayPhase("partial");
    setScreen("playPick");
  }, [playPhase]);

  const subTitle =
    screen === "playPick"
      ? t.gameType.title
      : screen === "playScope"
        ? t.team.title
        : screen === "campaignPick" ||
            screen === "campaignBouncer" ||
            screen === "campaignChapter"
          ? t.campaign.title
          : screen === "customize"
            ? t.customize.title
            : screen === "achievements"
              ? t.achievements.title
            : screen === "options"
              ? t.options.title
              : screen === "controls"
                ? t.controls.title
                : "";

  const panelHint = (text: string) => (
    <p className="font-ui text-xs text-center mt-2 menu-arena-ui__tagline">{text}</p>
  );

  const navBtn = (
    label: string,
    onClick: () => void,
    primary = false,
    disabled = false,
  ) => (
    <button
      type="button"
      className={primary ? "menu-nav-btn menu-nav-btn--primary" : "menu-nav-btn"}
      disabled={disabled}
      onClick={onClick}
    >
      {label}
    </button>
  );

  const showCharacterCard =
    screen === "home" || screen === "customize" || screen === "achievements";
  const widePanel =
    screen === "customize" || screen === "achievements" || screen === "playScope";

  return (
    <div className="menu-arena-root">
      <MenuArena
        playPhase={playPhase}
        playRunId={playRunId}
        chainsBroken={chainsBroken}
      />

      {showCharacterCard && <MenuCharacterCard />}

      <div
        className={[
          "menu-arena-ui",
          widePanel ? "menu-arena-ui--wide" : "",
        ]
          .filter(Boolean)
          .join(" ")}
      >
        <div className="menu-arena-ui__panel menu-panel-surface menu-panel-pad">
          {screen === "home" ? (
            <>
              <p className="menu-arena-ui__tagline font-ui">{t.game.subtitle}</p>
              <MenuNav
                onPlay={handlePlay}
                onCustomize={() => go("customize")}
                onAchievements={() => go("achievements")}
                onOptions={() => go("options")}
                onControls={() => go("controls")}
                onWorkshop={openWorkshop}
              />
            </>
          ) : (
            <div className="menu-arena-sub menu-panel-enter">
              {screen !== "playPick" && (
                <MenuBreadcrumb home={t.menu.breadcrumbHome} current={subTitle} />
              )}
              <MenuBackBar
                label={screen === "playPick" ? t.menu.back : t.menu.back}
                onBack={screen === "playPick" ? goHome : goBack}
              />

              {screen === "playPick" && (
                <>
                  <h2 className="font-display text-xl uppercase text-center mb-1 text-white">
                    {t.gameType.title}
                  </h2>
                  <p className="font-ui text-sm text-center mb-4 menu-arena-ui__tagline">
                    {t.menu.playPickHint}
                  </p>
                  <ul className="menu-nav-secondary list-none p-0 m-0 vstack gap-3">
                    <li>
                      {navBtn(t.gameType.quickBattle, () => {
                        playMenuSound("panel");
                        advanceToSoaring();
                        resumeScreenRef.current = "playScope";
                        sendN("PLAY")();
                        sendN("QUICK_BATTLE")();
                        setScreen("playScope");
                      }, true)}
                      {panelHint(t.gameType.quickBattleHint)}
                    </li>
                    <li>
                      {navBtn(t.gameType.campaign, () => {
                        playMenuSound("panel");
                        advanceToSoaring();
                        setScreen("campaignPick");
                      })}
                      {panelHint(t.gameType.campaignHint)}
                    </li>
                  </ul>
                </>
              )}

              {screen === "playScope" && <WsDuelPanel />}

              {screen === "campaignPick" && (
                <>
                  <h2 className="font-display text-xl uppercase text-center mb-4 text-white">
                    {t.campaign.title}
                  </h2>
                  <ul className="menu-nav-secondary list-none p-0 m-0 vstack gap-3">
                    <li>
                      {navBtn(t.campaign.local, () => {
                        playMenuSound("panel");
                        refreshProgress();
                        resumeScreenRef.current = "campaignBouncer";
                        setScreen("campaignBouncer");
                      }, true)}
                      {panelHint(t.campaign.localHint)}
                    </li>
                    <li>
                      {navBtn(t.campaign.online, () => {}, false, true)}
                      {panelHint(t.campaign.onlineSoon)}
                    </li>
                  </ul>
                </>
              )}

              {screen === "campaignBouncer" && (
                <>
                  <h2 className="font-display text-xl uppercase text-center mb-2 text-white">
                    {t.campaign.bouncerTitle}
                  </h2>
                  <p className="font-ui text-sm text-center mb-4 menu-arena-ui__tagline">
                    {t.campaign.bouncerHint}
                  </p>
                  <ul className="menu-nav-secondary list-none p-0 m-0 vstack gap-2">
                    {BOUNCER_CHAPTERS.map((chapter) => {
                      const unlocked = isChapterUnlocked(chapter.order);
                      return (
                        <li key={chapter.id}>
                          {navBtn(
                            pickL10n(chapter.title, lang),
                            () => {
                              if (!unlocked) return;
                              playMenuSound("panel");
                              setSelectedChapterId(chapter.id);
                              setScreen("campaignChapter");
                            },
                            unlocked,
                            !unlocked,
                          )}
                          {!unlocked && (
                            <p className="text-[10px] text-center text-gray-500 mt-1">
                              {t.campaign.chapterLocked}
                            </p>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                </>
              )}

              {screen === "campaignChapter" && selectedChapterId && (() => {
                const chapter = BOUNCER_CHAPTERS.find((c) => c.id === selectedChapterId);
                if (!chapter) return null;
                return (
                  <>
                    <h2 className="font-display text-lg uppercase text-center mb-2 text-white">
                      {pickL10n(chapter.title, lang)}
                    </h2>
                    <p className="font-ui text-xs text-center mb-1 text-cyan-300/80">
                      {t.campaign.chapterIntro}
                    </p>
                    <p className="font-ui text-sm text-center mb-4 menu-arena-ui__tagline leading-snug">
                      {pickL10n(chapter.intro, lang)}
                    </p>
                    {navBtn(t.campaign.chapterFight, () => startChapterBattle(chapter.id), true)}
                  </>
                );
              })()}

              {screen === "customize" && (
                <CustomizePanel
                  embedded
                  onOpenAchievements={() => go("achievements")}
                />
              )}
              {screen === "achievements" && <AchievementsPanel embedded />}
              {screen === "options" && <OptionsPanel embedded />}
              {screen === "controls" && <ControlsPanel embedded />}
            </div>
          )}
        </div>
      </div>

      <MenuFooter />
      <MenuArenaCursor />
    </div>
  );
}
