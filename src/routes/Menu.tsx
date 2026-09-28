import { GameContext } from "@/GameContext";
import {
  BOUNCER_CHAPTERS,
  pickL10n,
  type BouncerChapterId,
} from "@/campaign/bouncer";
import { getMaxUnlockedOrder, isChapterUnlocked } from "@/campaign/progress";
import { AccountPanel } from "@/components/AccountPanel";
import { AchievementsPanel } from "@/components/AchievementsPanel";
import { CustomizePanel } from "@/components/CustomizePanel";
import { ControlsPanel } from "@/components/ControlsPanel";
import { CreditsPanel } from "@/components/CreditsPanel";
import { DevLabPanel } from "@/components/DevLabPanel";
import { OptionsPanel } from "@/components/OptionsPanel";
import { MenuArena } from "@/components/menu/MenuArena";
import { MenuBreadcrumb } from "@/components/menu/MenuBreadcrumb";
import { MenuFooter } from "@/components/menu/MenuFooter";
import { MenuCharacterCard } from "@/components/menu/MenuCharacterCard";
import { MenuHomeAuth } from "@/components/menu/MenuHomeAuth";
import { MenuNav } from "@/components/menu/MenuNav";
import { MenuBackBar } from "@/components/menu/MenuSlidePanel";
import { WsDuelPanel } from "@/components/menu/WsDuelPanel";
import { DraftScreen } from "@/components/lobby/DraftScreen";
import { RoguelikeHub } from "@/components/lobby/RoguelikeHub";
import {
  LobbyScreen,
  type LobbyMode,
} from "@/components/lobby/LobbyScreen";
import { playMenuSound } from "@/audio";
import type { AiDifficultyId } from "@/battle/aiProfiles";
import {
  consumeBattleResult,
  QUICK_OPPONENT_HP_DEFAULT,
  setBattleDedicated,
  setBattleLab,
  setBattleLocal2P,
  setBattleQuick,
  setBattleRoguelike,
  setBattleTestArena,
  setBattleWeaponSandbox,
  type QuickOpponentHp,
} from "@/lib/battleConfig";
import { ENABLE_ONLINE_DUEL } from "@/lib/featureFlags";
import { isLabUnlocked } from "@/lib/labMode";
import type { LabFightPick } from "@/components/DevLabPanel";
import type { TestArenaPick } from "@/components/TestArenaPanel";
import type { WeaponSandboxPick } from "@/components/WeaponSandboxPanel";
import { buildTestArenaLoadout } from "@/loadout/testArenaLoadout";
import { e2eMatches, e2eOk, e2eSetPhase } from "@/dev/e2eHarness";
import { defaultLoadout, type FighterLoadout } from "@/loadout";
import { getRoomIdFromHash } from "@/net/room";
import { useNetSession } from "@/net/NetSessionContext";
import { mapRoleToDedicated, useWsSession } from "@/net/WsSessionContext";
import { parseDuelHash } from "@/net/wsClient";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import {
  applyTeamBattleConfig,
  emptyExtraSlots,
  type TeamSlot,
} from "@/team/teamSlots";
import { setBattleConfig } from "@/lib/battleConfig";
import {
  clearRoguelikeRun,
  getRoguelikeRun,
  resolveBattle,
  selectedPortal,
  startRoguelikeRun,
} from "@/roguelike/runState";
import { useViewportFlags } from "@/hooks/useViewportFlags";
import { useSettings, useTranslation } from "@/settings/SettingsContext";
import { useActor } from "@xstate/react";
import { useContext, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useKeyPressEvent } from "react-use";

type MenuScreen =
  | "home"
  | "account"
  | "customize"
  | "achievements"
  | "options"
  | "controls"
  | "credits"
  | "lab"
  | "playPick"
  | "lobby"
  | "draft"
  | "roguelike"
  | "playScope"
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
  const { coarse } = useViewportFlags();
  const lang = settings.language;
  const [screen, setScreen] = useState<MenuScreen>("home");
  const [selectedChapterId, setSelectedChapterId] = useState<BouncerChapterId | null>(
    null,
  );
  const [, setUnlockedOrder] = useState(() => getMaxUnlockedOrder());
  const resumeScreenRef = useRef<MenuScreen>("home");
  const wasBattleRef = useRef(false);
  const deepLinkBootstrappedRef = useRef(false);

  const [lobbyMode, setLobbyMode] = useState<LobbyMode>("vs");
  const [botDifficulty, setBotDifficulty] = useState<AiDifficultyId>("normal");
  const [opponentHp, setOpponentHp] = useState<QuickOpponentHp>(
    QUICK_OPPONENT_HP_DEFAULT,
  );
  const [extraSlots, setExtraSlots] = useState(emptyExtraSlots);
  const [, setDraftLoadouts] = useState<Record<string, FighterLoadout>>({});
  const [inviteCopied, setInviteCopied] = useState(false);
  const [labOpen, setLabOpen] = useState(() => isLabUnlocked());

  /** На телефоне локальных нет; на ПК — ты + 1 локальный (2 клавиатуры). */
  const allowLocalPlayers = !coarse;
  const maxLocalHumans = allowLocalPlayers ? 2 : 1;

  const lobbySlots: TeamSlot[] = useMemo(
    () => [
      { kind: "you", name: profile.name },
      extraSlots[2],
      extraSlots[3],
      extraSlots[4],
    ],
    [profile.name, extraSlots],
  );

  const lobbyHumans = useMemo(
    () =>
      lobbySlots.filter(
        (s) => s.kind === "you" || s.kind === "local" || s.kind === "remote",
      ).length,
    [lobbySlots],
  );

  const lobbyLocalCount = useMemo(
    () => lobbySlots.filter((s) => s.kind === "you" || s.kind === "local").length,
    [lobbySlots],
  );

  const canStartLobby = useMemo(() => {
    // Стандарт: 1v1 против бота — без пати.
    if (lobbyMode === "vs") return true;
    if (lobbyMode === "campaign") return lobbyLocalCount === 1 && lobbyHumans === 1;
    return lobbyHumans >= 1;
  }, [lobbyMode, lobbyHumans, lobbyLocalCount]);

  // Подтянуть remote-слоты из WS-лобби (не трогаем local).
  useEffect(() => {
    if (!ENABLE_ONLINE_DUEL || !ws.connected || screen !== "lobby") return;
    const owned = new Set(ws.ownedFighterIds);
    const remotes = ws.lobby.filter(
      (p) => p.fighterId !== "player" && !owned.has(p.fighterId),
    );
    setExtraSlots((prev) => {
      const next = { ...prev };
      const seats = [2, 3, 4] as const;
      for (const seat of seats) {
        if (next[seat].kind === "remote") next[seat] = { kind: "empty" };
      }
      let i = 0;
      for (const seat of seats) {
        if (i >= remotes.length) break;
        if (next[seat].kind !== "empty") continue;
        const p = remotes[i]!;
        next[seat] = {
          kind: "remote",
          peerId: p.fighterId,
          name: p.name || p.fighterId,
        };
        i += 1;
      }
      return next;
    });
  }, [ws.connected, ws.lobby, ws.ownedFighterIds, screen]);

  const refreshProgress = useCallback(() => {
    setUnlockedOrder(getMaxUnlockedOrder());
  }, []);

  useEffect(() => {
    if (coarse && screen === "controls") setScreen("home");
  }, [coarse, screen]);

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
      setScreen("lobby");
      setLobbyMode("vs");
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      ws.joinByCode(duel.code, profile.name);
      window.history.replaceState(
        null,
        "",
        `${window.location.pathname}${window.location.search}`,
      );
      return;
    }
    const roomId = getRoomIdFromHash();
    if (!roomId) return;
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
    if (e2eMatches("lobby")) {
      e2eSetPhase("running");
      setScreen("lobby");
      const t = setTimeout(
        () => e2eOk({ screen: "lobby", mode: lobbyMode, humans: lobbyHumans }),
        900,
      );
      return () => clearTimeout(t);
    }
    if (e2eMatches("draft") || e2eMatches("roguelike")) {
      e2eSetPhase("running");
      setLobbyMode("roguelike");
      const ids =
        lobbyHumans > 1 ? ["you", "local2"] : ["you"];
      const loadouts: Record<string, FighterLoadout> = {};
      for (const id of ids) loadouts[id] = defaultLoadout();
      startRoguelikeRun(loadouts, "normal", {
        playerIds: ids,
        playerNames: { you: profile.name, local2: "P2" },
        seed: 42,
      });
      setScreen("roguelike");
      const timer = setTimeout(
        () =>
          e2eOk({
            screen: "roguelike",
            playerCount: Math.max(1, lobbyHumans),
            floor: 1,
            portals: getRoguelikeRun()?.map.floors[0]?.portals.length ?? 0,
          }),
        900,
      );
      return () => clearTimeout(timer);
    }
    if (e2eMatches("quick")) {
      e2eSetPhase("running");
      setBattleQuick();
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      sendN("START_BATTLE")();
    }
    if (e2eMatches("workshop") || e2eMatches("workshopFight")) {
      e2eSetPhase("running");
      sendN("WORKSHOP")();
    }
    return undefined;
  }, [sendN, lobbyMode, lobbyHumans, profile.name]);

  useEffect(() => {
    if (guestStartSignal === 0) return;
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
      const run = getRoguelikeRun();
      if (run && (run.phase === "battle" || resumeScreenRef.current === "roguelike")) {
        const result = consumeBattleResult();
        const won = result?.winner === "player";
        resolveBattle(Boolean(won));
        setScreen("roguelike");
        refreshProgress();
        return;
      }
      setScreen(resumeScreenRef.current);
      refreshProgress();
    }
  }, [gameA, refreshProgress]);

  const go = useCallback(
    (
      next:
        | "account"
        | "customize"
        | "achievements"
        | "options"
        | "controls"
        | "credits"
        | "lab",
    ) => {
      playMenuSound("panel");
      setScreen(next);
    },
    [],
  );

  const goBack = useCallback(() => {
    playMenuSound("click");
    setScreen((prev) => {
      switch (prev) {
        case "draft":
        case "roguelike":
          return "lobby";
        case "lobby":
          return "home";
        case "playScope":
          return "lobby";
        case "campaignChapter":
          return "campaignBouncer";
        case "campaignBouncer":
          return "playPick";
        case "playPick":
          return "home";
        default:
          return "home";
      }
    });
  }, []);

  const goHome = useCallback(() => {
    playMenuSound("click");
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

  const startQuickSolo = useCallback(() => {
    playMenuSound("play");
    resumeScreenRef.current = "home";
    setBattleQuick({ opponentHp });
    sendN("PLAY")();
    sendN("QUICK_BATTLE")();
    sendN("START_BATTLE")();
  }, [sendN, opponentHp]);

  const openWorkshop = useCallback(() => {
    playMenuSound("panel");
    sendN("WORKSHOP")();
  }, [sendN]);

  const stripStrikeLabQuery = useCallback(() => {
    // Снять ?lab=1, чтобы Battle1Player не ушёл в старый StrikeLab.
    try {
      const url = new URL(window.location.href);
      const v = url.searchParams.get("lab");
      if (v === "1" || v === "strike") {
        url.searchParams.delete("lab");
        window.history.replaceState({}, "", url);
      }
    } catch {
      /* ignore */
    }
  }, []);

  const startLabFight = useCallback(
    (pick: LabFightPick) => {
      resumeScreenRef.current = "lab";
      stripStrikeLabQuery();
      setBattleLab(pick);
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      sendN("START_BATTLE")();
    },
    [sendN, stripStrikeLabQuery],
  );

  const startTestArena = useCallback(
    (pick: TestArenaPick) => {
      resumeScreenRef.current = "lab";
      stripStrikeLabQuery();
      const built = buildTestArenaLoadout(pick.abilities, pick.items);
      setBattleTestArena({
        playerHp: pick.playerHp,
        opponentHp: pick.opponentHp,
        opponentCount: pick.opponentCount,
        arenaItemIds: pick.arenaWeaponIds,
        loadout: built.loadout,
        extraItems: built.extraItems,
        castAbilities: built.castAbilities,
      });
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      sendN("START_BATTLE")();
    },
    [sendN, stripStrikeLabQuery],
  );

  const startWeaponSandbox = useCallback(
    (pick: WeaponSandboxPick) => {
      resumeScreenRef.current = "lab";
      stripStrikeLabQuery();
      setBattleWeaponSandbox({ arenaItemIds: pick.arenaItemIds });
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      sendN("START_BATTLE")();
    },
    [sendN, stripStrikeLabQuery],
  );

  useKeyPressEvent("Escape", () => {
    if (screen === "home") return;
    if (
      screen === "account" ||
      screen === "customize" ||
      screen === "achievements" ||
      screen === "options" ||
      screen === "controls" ||
      screen === "credits" ||
      screen === "lab"
    ) {
      goHome();
    } else {
      goBack();
    }
  });

  const startFromLobby = useCallback(() => {
    playMenuSound("play");
    resumeScreenRef.current = "lobby";
    if (lobbyMode === "campaign") {
      refreshProgress();
      setScreen("campaignBouncer");
      return;
    }
    if (lobbyMode === "roguelike") {
      const ids = ["you"] as string[];
      const names: Record<string, string> = { you: profile.name };
      const loadouts: Record<string, FighterLoadout> = {
        you: defaultLoadout(),
      };
      let n = 1;
      for (const seat of [2, 3, 4] as const) {
        if (extraSlots[seat].kind === "local") {
          const id = `local${n + 1}`;
          ids.push(id);
          names[id] = extraSlots[seat].name || `P${n + 1}`;
          loadouts[id] = defaultLoadout();
          n += 1;
        }
      }
      startRoguelikeRun(loadouts, botDifficulty, {
        playerIds: ids,
        playerNames: names,
      });
      resumeScreenRef.current = "roguelike";
      setScreen("roguelike");
      return;
    }
    if (lobbyMode === "vs") {
      // Стандартный режим: 1v1 против бота, только выбор HP.
      setBattleQuick({ opponentHp });
      sendN("PLAY")();
      sendN("QUICK_BATTLE")();
      sendN("START_BATTLE")();
      return;
    }
    // Остальное → 1 vs 1 бот.
    setBattleQuick({ opponentHp });
    sendN("PLAY")();
    sendN("QUICK_BATTLE")();
    sendN("START_BATTLE")();
  }, [
    lobbyMode,
    opponentHp,
    refreshProgress,
    sendN,
    botDifficulty,
    profile.name,
    extraSlots,
  ]);

  const enterRoguelikeBattle = useCallback(() => {
    const run = getRoguelikeRun();
    const portal = selectedPortal();
    if (!run || !portal) return;
    resumeScreenRef.current = "roguelike";
    setBattleRoguelike({
      floor: run.floor,
      bots: portal.botCount,
      difficulty: portal.difficulty,
      loadouts: run.loadouts,
    });
    sendN("PLAY")();
    sendN("QUICK_BATTLE")();
    sendN("START_BATTLE")();
  }, [sendN]);

  const handlePlay = useCallback(() => {
    playMenuSound("play");
    setScreen("lobby");
  }, []);

  const subTitle =
    screen === "lobby" || screen === "draft"
      ? t.lobby.title
      : screen === "roguelike"
        ? t.roguelike.title
      : screen === "playPick"
        ? t.gameType.title
        : screen === "playScope"
          ? t.team.title
          : screen === "campaignBouncer" || screen === "campaignChapter"
            ? t.campaign.title
            : screen === "account"
              ? t.account.title
              : screen === "customize"
                ? t.customize.title
                : screen === "achievements"
                  ? t.achievements.title
                  : screen === "options"
                    ? t.options.title
                    : screen === "controls"
                      ? t.controls.title
                      : screen === "credits"
                        ? t.credits.title
                        : screen === "lab"
                          ? t.lab.title
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
      // В этом меню отключённой бывает только глава, закрытая прогрессом:
      // отмечаем её явно, чтобы проверки не путали её со сломанной кнопкой.
      data-locked={disabled ? "true" : undefined}
      onClick={onClick}
    >
      {label}
    </button>
  );

  const showCharacterCard =
    screen === "account" ||
    screen === "customize" ||
    screen === "achievements";
  const widePanel =
    screen === "customize" ||
    screen === "achievements" ||
    screen === "playScope" ||
    screen === "controls" ||
    screen === "lobby" ||
    screen === "draft" ||
    screen === "roguelike" ||
    screen === "lab";

  return (
    <div className="menu-arena-root menu-arena-root--simple">
      <MenuArena />

      {showCharacterCard && <MenuCharacterCard />}

      <div
        className={[
          "menu-arena-ui",
          "menu-arena-ui--simple",
          widePanel ? "menu-arena-ui--wide" : "",
          showCharacterCard ? "menu-arena-ui--with-fighter" : "",
          screen === "controls" ? "menu-arena-ui--controls" : "",
          screen === "roguelike" ? "menu-arena-ui--roguelike" : "",
          screen === "lab" ? "menu-arena-ui--lab" : "",
        ]
          .filter(Boolean)
          .join(" ")}
      >
        <div
          className={[
            "menu-arena-ui__panel",
            "menu-panel-surface",
            "menu-panel-pad",
            screen === "roguelike" ? "menu-arena-ui__panel--roguelike" : "",
            screen === "lab" ? "menu-arena-ui__panel--lab" : "",
          ]
            .filter(Boolean)
            .join(" ")}
        >
          {screen === "home" ? (
            <>
              <h1 className="menu-home-brand font-display">
                <span className="menu-home-brand__title">{t.game.title}</span>
                <span className="menu-home-brand__accent">{t.game.titleAccent}</span>
              </h1>
              <p className="menu-arena-ui__tagline font-hand">{t.game.subtitle}</p>
              <MenuHomeAuth onOpenAccount={() => go("account")} />
              <MenuNav
                onPlay={handlePlay}
                onAccount={() => go("account")}
                onCustomize={() => go("customize")}
                onAchievements={() => go("achievements")}
                onOptions={() => go("options")}
                onControls={() => go("controls")}
                onCredits={() => go("credits")}
                onLab={labOpen ? () => go("lab") : undefined}
                onWorkshop={openWorkshop}
              />
            </>
          ) : (
            <div className="menu-arena-sub menu-panel-enter">
              {screen !== "playPick" && screen !== "lobby" && (
                <MenuBreadcrumb
                  home={t.menu.breadcrumbHome}
                  current={subTitle}
                  onHome={goHome}
                />
              )}
              <MenuBackBar
                label={t.menu.back}
                onBack={
                  screen === "playPick" || screen === "lobby" ? goHome : goBack
                }
              />

              {screen === "lobby" && (
                <LobbyScreen
                  slots={lobbySlots}
                  mode={lobbyMode}
                  onModeChange={setLobbyMode}
                  botDifficulty={botDifficulty}
                  onBotDifficultyChange={setBotDifficulty}
                  opponentHp={opponentHp}
                  onOpponentHpChange={setOpponentHp}
                  canStart={canStartLobby}
                  onStart={startFromLobby}
                  allowLocal={allowLocalPlayers}
                  localCount={lobbyLocalCount}
                  maxLocal={maxLocalHumans}
                  inviteEnabled={ENABLE_ONLINE_DUEL}
                  inviteUrl={ws.shareUrl}
                  inviteCode={ws.duelCode}
                  inviteCopied={inviteCopied}
                  onlinePlayers={ws.lobby.length}
                  isOnline={ENABLE_ONLINE_DUEL && ws.connected}
                  isHost={ws.role === "player" || !ws.connected}
                  myReady={ws.myReady}
                  onToggleReady={() => {
                    playMenuSound("click");
                    ws.sendReady(!ws.myReady);
                  }}
                  onCopyInvite={() => {
                    const text = ws.shareUrl || ws.duelCode;
                    if (!text) return;
                    void navigator.clipboard?.writeText(text).then(() => {
                      setInviteCopied(true);
                      window.setTimeout(() => setInviteCopied(false), 1600);
                    });
                  }}
                  onAddLocal={() => {
                    if (!allowLocalPlayers) return;
                    if (lobbyLocalCount >= maxLocalHumans) return;
                    playMenuSound("panel");
                    setExtraSlots((prev) => {
                      const next = { ...prev };
                      for (const seat of [2, 3, 4] as const) {
                        if (next[seat].kind === "empty") {
                          next[seat] = {
                            kind: "local",
                            name: `P${seat}`,
                            seat,
                          };
                          break;
                        }
                      }
                      return next;
                    });
                    if (ws.connected) ws.claimLocalSlot("P2");
                  }}
                  onInvite={() => {
                    playMenuSound("panel");
                    if (!ENABLE_ONLINE_DUEL) return;
                    if (!ws.connected) ws.createRoom(profile.name);
                    setInviteCopied(false);
                  }}
                  onRemove={(index) => {
                    playMenuSound("click");
                    const seat = (index + 1) as 2 | 3 | 4;
                    if (seat < 2 || seat > 4) return;
                    const removed = extraSlots[seat];
                    if (removed.kind === "remote" && ws.connected) {
                      /* кик remote с сервера пока не поддержан — только UI */
                    }
                    if (
                      removed.kind === "local" &&
                      ws.connected &&
                      ws.ownedFighterIds.length > 1
                    ) {
                      const localId = ws.ownedFighterIds.find(
                        (id) => id !== "player",
                      );
                      if (localId) ws.releaseLocalSlot(localId);
                    }
                    setExtraSlots((prev) => ({
                      ...prev,
                      [seat]: { kind: "empty" },
                    }));
                  }}
                />
              )}

              {screen === "draft" && (
                <DraftScreen
                  playerCount={lobbyHumans}
                  localPlayerIds={
                    lobbyHumans > 1 ? ["you", "local2"] : ["you"]
                  }
                  onBack={() => setScreen("lobby")}
                  onConfirm={(loadouts) => {
                    setDraftLoadouts(loadouts);
                    startRoguelikeRun(loadouts, botDifficulty, {
                      playerIds: Object.keys(loadouts),
                      playerNames: { you: profile.name },
                    });
                    setScreen("roguelike");
                  }}
                />
              )}

              {screen === "roguelike" && (
                <RoguelikeHub
                  key={getRoguelikeRun()?.hubEpoch ?? 0}
                  localPlayerId="you"
                  onBack={() => {
                    clearRoguelikeRun();
                    setScreen("lobby");
                  }}
                  onLeaveRun={() => {
                    clearRoguelikeRun();
                    setScreen("lobby");
                  }}
                  onEnterBattle={enterRoguelikeBattle}
                />
              )}

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
                      {navBtn(t.gameType.quickBattle, startQuickSolo, true)}
                      {panelHint(t.gameType.quickBattleHint)}
                    </li>
                    <li>
                      {navBtn(t.playScope.local2p, () => {
                        playMenuSound("play");
                        resumeScreenRef.current = "playPick";
                        setBattleLocal2P();
                        sendN("PLAY")();
                        sendN("QUICK_BATTLE")();
                        sendN("LOCAL_2P")();
                      })}
                      {panelHint(t.playScope.local2pHint)}
                    </li>
                    {ENABLE_ONLINE_DUEL && (
                      <li>
                        {navBtn(t.playScope.multiplayer, () => {
                          playMenuSound("panel");
                          resumeScreenRef.current = "playScope";
                          sendN("PLAY")();
                          sendN("QUICK_BATTLE")();
                          setScreen("playScope");
                        })}
                        {panelHint(t.playScope.multiplayerSoon)}
                      </li>
                    )}
                    <li>
                      {navBtn(t.gameType.campaign, () => {
                        playMenuSound("panel");
                        refreshProgress();
                        resumeScreenRef.current = "campaignBouncer";
                        setScreen("campaignBouncer");
                      })}
                      {panelHint(t.gameType.campaignHint)}
                    </li>
                  </ul>
                </>
              )}

              {screen === "playScope" && <WsDuelPanel />}

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

              {screen === "account" && <AccountPanel />}
              {screen === "customize" && (
                <CustomizePanel
                  embedded
                  onOpenAchievements={() => go("achievements")}
                />
              )}
              {screen === "achievements" && <AchievementsPanel embedded />}
              {screen === "options" && <OptionsPanel embedded />}
              {screen === "controls" && <ControlsPanel embedded />}
              {screen === "credits" && <CreditsPanel embedded />}
              {screen === "lab" && (
                <DevLabPanel
                  onStartFight={startLabFight}
                  onStartArena={startTestArena}
                  onStartSandbox={startWeaponSandbox}
                />
              )}
            </div>
          )}
        </div>
      </div>

      <MenuFooter
        onLabUnlocked={() => {
          setLabOpen(true);
        }}
      />
    </div>
  );
}
