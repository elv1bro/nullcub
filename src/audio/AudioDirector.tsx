import { GameContext } from "@/GameContext";
import { useActor } from "@xstate/react";
import { useContext, useEffect } from "react";
import { playBattleMusic, playMenuMusic, disposeMusic } from "./music";
import { playGongSound, preloadCombatAudio, setHeartbeatLevel } from "./sfx";
import { NowPlaying } from "./NowPlaying";

/**
 * Следит за состоянием игры: в меню крутит тему меню, в бою — боевой
 * плейлист (плюс гонг на старте), и показывает виджет «сейчас играет».
 */
export function AudioDirector() {
  const { gameM } = useContext(GameContext);
  const [gameA] = useActor(gameM);
  const inBattle = gameA.matches("battle");

  useEffect(() => {
    if (inBattle) {
      preloadCombatAudio();
      playGongSound();
      playBattleMusic();
    } else {
      setHeartbeatLevel(0);
      playMenuMusic();
    }
  }, [inBattle]);

  useEffect(() => () => disposeMusic(), []);

  return inBattle ? <NowPlaying /> : null;
}
