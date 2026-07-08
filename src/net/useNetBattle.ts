import { useNetSession } from "@/net/NetSessionContext";
import {
  decodeBodiesOrdered,
  encodeBodiesOrdered,
} from "@/net/snapshot";
import {
  BATTLE_STATE_HZ,
  INPUT_HZ,
  SNAPSHOT_HZ,
  type NetBattleStatePayload,
  type NetInputPayload,
} from "@/net/protocol";
import { PLAYER_MOVE_SPEED } from "@/lib/battleTuning";
import { moveBody } from "@/lib/moveBody";
import { useEngine, useEventBeforeUpdate } from "@1.framework/matter4react";
import Matter, { Vector, type Body, type Composite } from "matter-js";
import {
  useEffect,
  useRef,
  useState,
  type MutableRefObject,
  type RefObject,
} from "react";
import { getBattleConfig } from "@/lib/battleConfig";

/** Детерминированный порядок тел для P2P (как на dedicated) — body.id у пиров не совпадают. */
function orderedBodiesFromComposites(composites: Composite[]): Body[] {
  return composites.flatMap((c) => c.bodies);
}

export function useNetBattleHost(composites: Composite[], enabled: boolean): void {
  const engine = useEngine();
  const net = useNetSession();
  const tickRef = useRef(0);
  const compositesRef = useRef(composites);
  compositesRef.current = composites;

  useEffect(() => {
    if (!enabled || !net.actions || !net.isHost) return;
    const [sendSnapshot] = net.actions.snapshot;
    const interval = setInterval(() => {
      tickRef.current++;
      const bodies = encodeBodiesOrdered(
        orderedBodiesFromComposites(compositesRef.current),
      );
      sendSnapshot(
        { tick: tickRef.current, t: performance.now(), bodies },
        [],
      );
    }, 1000 / SNAPSHOT_HZ);
    return () => clearInterval(interval);
  }, [enabled, net.actions, net.isHost, engine]);
}

export function useNetBattleGuest(
  composites: Composite[],
  enabled: boolean,
): void {
  const engine = useEngine();
  const net = useNetSession();
  const compositesRef = useRef(composites);
  compositesRef.current = composites;

  useEffect(() => {
    if (!enabled || !net.actions || net.isHost) return;
    const [, onSnapshot] = net.actions.snapshot;
    onSnapshot((payload) => {
      const data =
        payload.bodies instanceof Float32Array
          ? payload.bodies
          : new Float32Array(payload.bodies as unknown as number[]);
      decodeBodiesOrdered(
        data,
        orderedBodiesFromComposites(compositesRef.current),
        0.35,
      );
    });
  }, [enabled, net.actions, net.isHost, engine]);
}

export function useNetInputSender(
  readMove: () => Vector,
  grabL: boolean | (() => boolean),
  grabR: boolean | (() => boolean),
  enabled: boolean,
  abilityFlags?: RefObject<{
    dash: boolean;
    flip: boolean;
    freeze: boolean;
    reset: boolean;
  }>,
): void {
  const net = useNetSession();
  const seqRef = useRef(0);

  useEffect(() => {
    if (!enabled || !net.actions || net.isHost) return;
    const [sendInput] = net.actions.input;
    const interval = setInterval(() => {
      const move = readMove();
      const flags = abilityFlags?.current;
      const payload: NetInputPayload = {
        seq: seqRef.current++,
        t: performance.now(),
        move: { x: move.x, y: move.y },
        grabL: typeof grabL === "function" ? grabL() : grabL,
        grabR: typeof grabR === "function" ? grabR() : grabR,
        dash: flags?.dash ?? false,
        flip: flags?.flip ?? false,
        freeze: flags?.freeze ?? false,
        reset: flags?.reset ?? false,
      };
      sendInput(payload, []);
      if (flags) {
        flags.dash = false;
        flags.flip = false;
        flags.freeze = false;
        flags.reset = false;
      }
    }, 1000 / INPUT_HZ);
    return () => clearInterval(interval);
  }, [enabled, net.actions, net.isHost, readMove, grabL, grabR, abilityFlags]);
}

export function useNetInputReceiver(
  enabled: boolean,
): RefObject<NetInputPayload | null> {
  const net = useNetSession();
  const latestRef = useRef<NetInputPayload | null>(null);

  useEffect(() => {
    if (!enabled || !net.actions || !net.isHost) return;
    const [, onInput] = net.actions.input;
    onInput((payload) => {
      latestRef.current = payload;
    });
  }, [enabled, net.actions, net.isHost]);

  return latestRef;
}

export function useNetRemoteOpponentMovement(
  opponentHeadRef: MutableRefObject<Body | undefined>,
  remoteInputRef: RefObject<NetInputPayload | null>,
  disabledRef: MutableRefObject<boolean>,
  speedMultRef?: MutableRefObject<number>,
  enabled = true,
): void {
  useEventBeforeUpdate(
    (event: Matter.IEventTimestamped<Matter.Engine>) => {
      if (!enabled || disabledRef.current) return;
      const input = remoteInputRef.current;
      const head = opponentHeadRef.current;
      if (!input || !head) return;
      const vector = Vector.create(input.move.x, input.move.y);
      if (vector.x === 0 && vector.y === 0) return;
      const speed = PLAYER_MOVE_SPEED * (speedMultRef?.current ?? 1);
      moveBody(head)(event, vector, speed);
    },
    [enabled, opponentHeadRef, remoteInputRef, disabledRef, speedMultRef],
  );
}

export function useNetRemoteGrabHeld(
  remoteInputRef: RefObject<NetInputPayload | null>,
  leftHeldRef: MutableRefObject<boolean>,
  rightHeldRef: MutableRefObject<boolean>,
  enabled: boolean,
): void {
  useEffect(() => {
    if (!enabled) return;
    let raf = 0;
    const tick = () => {
      const input = remoteInputRef.current;
      if (input) {
        leftHeldRef.current = input.grabL;
        rightHeldRef.current = input.grabR;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [enabled, remoteInputRef, leftHeldRef, rightHeldRef]);
}

export function useNetBattleBroadcast(
  enabled: boolean,
  state: NetBattleStatePayload,
): void {
  const net = useNetSession();
  const stateRef = useRef(state);
  stateRef.current = state;

  useEffect(() => {
    if (!enabled || !net.actions || !net.isHost) return;
    const [sendState] = net.actions.battleState;
    const interval = setInterval(() => {
      sendState(stateRef.current, []);
    }, 1000 / BATTLE_STATE_HZ);
    return () => clearInterval(interval);
  }, [enabled, net.actions, net.isHost]);
}

export function useNetPing(enabled: boolean): number {
  const net = useNetSession();
  const [pingMs, setPingMs] = useState(0);

  useEffect(() => {
    if (!enabled || !net.room) return;
    const peer = net.peers[0];
    if (!peer) {
      setPingMs(0);
      return;
    }

    let cancelled = false;
    const tick = async () => {
      if (cancelled || !net.room) return;
      try {
        const ms = await net.room.ping(peer.id);
        if (!cancelled) setPingMs(Math.round(ms));
      } catch {
        if (!cancelled) setPingMs(0);
      }
    };

    void tick();
    const interval = setInterval(() => void tick(), 2000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [enabled, net.room, net.peers]);

  return pingMs;
}

export function isNetworkBattle(): boolean {
  return getBattleConfig().kind === "network";
}

export function networkRole(): "host" | "guest" {
  const cfg = getBattleConfig();
  return cfg.kind === "network" ? cfg.role : "host";
}

export function isNetworkHost(): boolean {
  const cfg = getBattleConfig();
  return cfg.kind === "network" && cfg.role === "host";
}

export function isNetworkGuest(): boolean {
  const cfg = getBattleConfig();
  return cfg.kind === "network" && cfg.role === "guest";
}
