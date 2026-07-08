import { useEngine, useEventBeforeUpdate } from "@1.framework/matter4react";
import Matter, { type Composite, type Engine } from "matter-js";
import { useEffect, useRef, useState, type MutableRefObject } from "react";
import { createBattleSession, type BattleSession } from "./battleSession";
import type {
  BattleSessionConfig,
  CoreFighterSpec,
  FighterRole,
} from "./types";
import type { NetInputPayload } from "@/net/protocol";
import type { BattleEventMap } from "./events";

export interface UseBattleSessionOpts {
  enabled: boolean;
  arenaSize: number;
  fighters: CoreFighterSpec[] | null;
  playerCompositeId?: number;
  opponentCompositeId?: number;
  itemComposites?: Composite[];
  battleStartMs?: number;
  /** matter4react: симуляция без Engine.update (Runner делает update). */
  externalRunner?: boolean;
  /** Вызвать beginBattle после N тиков settle (локальный паритет с сервером). */
  settleTicksBeforeBegin?: number;
  onHit?: (payload: BattleEventMap["hit"]) => void;
  onKnockout?: (payload: BattleEventMap["knockout"]) => void;
  onBattleEnd?: (payload: BattleEventMap["battleEnd"]) => void;
  onDisarm?: (fighterCompositeId: number, item: Composite) => void;
}

export interface BattleSessionView {
  sessionRef: MutableRefObject<BattleSession | null>;
  playerHp: number;
  opponentHp: number;
  battleOver: boolean;
  winner: FighterRole | null;
  setPlayerInput: (input: NetInputPayload) => void;
  setOpponentInput: (input: NetInputPayload) => void;
}

const DEFAULT_LOCAL_SETTLE_TICKS = 3;

export function useBattleSession(opts: UseBattleSessionOpts): BattleSessionView {
  const engine = useEngine();
  const sessionRef = useRef<BattleSession | null>(null);
  const [playerHp, setPlayerHp] = useState(1000);
  const [opponentHp, setOpponentHp] = useState(1000);
  const [battleOver, setBattleOver] = useState(false);
  const [winner, setWinner] = useState<FighterRole | null>(null);
  const settleLeftRef = useRef(0);
  const onHitRef = useRef(opts.onHit);
  const onKnockoutRef = useRef(opts.onKnockout);
  const onBattleEndRef = useRef(opts.onBattleEnd);
  const onDisarmRef = useRef(opts.onDisarm);
  onHitRef.current = opts.onHit;
  onKnockoutRef.current = opts.onKnockout;
  onBattleEndRef.current = opts.onBattleEnd;
  onDisarmRef.current = opts.onDisarm;

  useEffect(() => {
    if (!opts.enabled || !opts.fighters?.length) {
      sessionRef.current?.destroy();
      sessionRef.current = null;
      return;
    }

    const settleTicks =
      opts.settleTicksBeforeBegin ?? DEFAULT_LOCAL_SETTLE_TICKS;

    const config: BattleSessionConfig = {
      arenaSize: opts.arenaSize,
      fighters: opts.fighters,
      itemComposites: opts.itemComposites,
      battleStartMs: opts.battleStartMs ?? performance.now(),
      playerCompositeId: opts.playerCompositeId,
      opponentCompositeId: opts.opponentCompositeId,
      engine,
      compositesInWorld: true,
      damageLocked: settleTicks > 0,
    };

    const session = createBattleSession(config);
    sessionRef.current = session;
    settleLeftRef.current = settleTicks;
    session.setDisarmHandler((compositeId, item) => {
      onDisarmRef.current?.(compositeId, item);
    });

    setPlayerHp(session.getHp("player"));
    setOpponentHp(session.getHp("opponent"));
    setBattleOver(false);
    setWinner(null);

    const offHit = session.events.on("hit", (p) => {
      onHitRef.current?.(p);
      const nextPlayer = session.getHp("player");
      const nextOpponent = session.getHp("opponent");
      setPlayerHp((prev) => (prev === nextPlayer ? prev : nextPlayer));
      setOpponentHp((prev) => (prev === nextOpponent ? prev : nextOpponent));
    });
    const offKo = session.events.on("knockout", (p) =>
      onKnockoutRef.current?.(p),
    );
    const offEnd = session.events.on("battleEnd", (p) => {
      setBattleOver(true);
      setWinner(p.winner);
      onBattleEndRef.current?.(p);
    });

    return () => {
      offHit();
      offKo();
      offEnd();
      session.destroy();
      sessionRef.current = null;
    };
  }, [
    opts.enabled,
    opts.fighters,
    opts.arenaSize,
    opts.playerCompositeId,
    opts.opponentCompositeId,
    opts.settleTicksBeforeBegin,
    opts.itemComposites,
    engine,
  ]);

  useEventBeforeUpdate(
    (event: Matter.IEventTimestamped<Engine>) => {
      const session = sessionRef.current;
      if (!session || !opts.enabled) return;
      const dt = event.delta ?? 1000 / 60;
      session.tick(dt, !opts.externalRunner);

      if (settleLeftRef.current > 0) {
        settleLeftRef.current -= 1;
        if (settleLeftRef.current === 0 && session.isDamageLocked()) {
          session.beginBattle();
        }
      }

      if (!battleOver) {
        const nextPlayer = session.getHp("player");
        const nextOpponent = session.getHp("opponent");
        setPlayerHp((prev) => (prev === nextPlayer ? prev : nextPlayer));
        setOpponentHp((prev) => (prev === nextOpponent ? prev : nextOpponent));
        if (session.isBattleOver()) {
          setBattleOver(true);
          setWinner(session.resolveWinner());
        }
      }
    },
    [opts.enabled, opts.externalRunner, battleOver],
  );

  const setPlayerInput = (input: NetInputPayload) => {
    sessionRef.current?.setInput("player", input);
  };
  const setOpponentInput = (input: NetInputPayload) => {
    sessionRef.current?.setInput("opponent", input);
  };

  return {
    sessionRef,
    playerHp,
    opponentHp,
    battleOver,
    winner,
    setPlayerInput,
    setOpponentInput,
  };
}
