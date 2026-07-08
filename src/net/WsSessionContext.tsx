import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PropsWithChildren,
} from "react";
import type { WsLobbyPlayer } from "./transport";
import {
  buildDuelCode,
  buildDuelShareUrl,
  buildWsUrl,
  defaultWsUrl,
  parseDuelCode,
  randomDuelRoomId,
  setDuelHash,
  WsNetTransport,
} from "./wsClient";

export type WsPhase = "idle" | "connecting" | "lobby" | "battle";

export interface WsSessionValue {
  phase: WsPhase;
  wsUrl: string | null;
  roomId: string | null;
  role: "player" | "opponent" | null;
  duelCode: string | null;
  shareUrl: string | null;
  lobby: WsLobbyPlayer[];
  myReady: boolean;
  error: string | null;
  connected: boolean;
  transport: WsNetTransport | null;
  battleStartSignal: number;
  createRoom: (name: string, roomId?: string) => void;
  connectToRoom: (
    name: string,
    roomId: string,
    joinRole: "player" | "opponent",
    serverUrl?: string,
  ) => void;
  joinByCode: (code: string, name: string) => void;
  sendReady: (ready: boolean) => void;
  disconnect: () => void;
  clearBattleStartSignal: () => void;
}

const WsSessionContext = createContext<WsSessionValue | null>(null);

function mapRoleToDedicated(role: "player" | "opponent"): "host" | "guest" {
  return role === "player" ? "host" : "guest";
}

export { mapRoleToDedicated };

export function WsSessionProvider({ children }: PropsWithChildren) {
  const [phase, setPhase] = useState<WsPhase>("idle");
  const [wsUrl, setWsUrl] = useState<string | null>(null);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [role, setRole] = useState<"player" | "opponent" | null>(null);
  const [duelCode, setDuelCodeState] = useState<string | null>(null);
  const [shareUrl, setShareUrl] = useState<string | null>(null);
  const [lobby, setLobby] = useState<WsLobbyPlayer[]>([]);
  const [myReady, setMyReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [connected, setConnected] = useState(false);
  const [transport, setTransport] = useState<WsNetTransport | null>(null);
  const [battleStartSignal, setBattleStartSignal] = useState(0);

  const transportRef = useRef<WsNetTransport | null>(null);
  const roleRef = useRef<"player" | "opponent" | null>(null);
  const phaseRef = useRef<WsPhase>("idle");
  const nameRef = useRef("Player");

  roleRef.current = role;
  phaseRef.current = phase;

  const teardown = useCallback(() => {
    transportRef.current?.close();
    transportRef.current = null;
    setTransport(null);
    setConnected(false);
    setWsUrl(null);
    setRoomId(null);
    setRole(null);
    setDuelCodeState(null);
    setShareUrl(null);
    setLobby([]);
    setMyReady(false);
    setError(null);
    setPhase("idle");
  }, []);

  const wireTransport = useCallback(
    (
      url: string,
      room: string,
      name: string,
      joinRole?: "player" | "opponent",
    ) => {
      teardown();
      setPhase("connecting");
      setError(null);
      nameRef.current = name;

      let closed = false;
      const t = new WsNetTransport(
        buildWsUrl(url, room),
        (welcome) => {
          roleRef.current = welcome.role;
          setRole(welcome.role);
          setWsUrl(url);
          setRoomId(room);
          setPhase("lobby");
          setConnected(true);
        },
        (msg) => setError(msg),
      );
      transportRef.current = t;
      setTransport(t);

      t.onOpen(() => {
        if (closed) return;
        t.join(room, name, joinRole);
      });

      t.onClose((_code, reason) => {
        if (closed) return;
        setConnected(false);
        setError(reason || "disconnected");
        if (phaseRef.current === "battle" || phaseRef.current === "lobby") {
          setPhase("idle");
        }
      });

      t.onOpponentLeft(() => {
        setError("opponent left");
      });

      t.onLobby((players) => {
        setLobby(players);
        const me = players.find((p) => p.fighterId === roleRef.current);
        if (me) setMyReady(me.ready);
        if (phaseRef.current === "battle" && players.length >= 1) {
          const allReady = players.length >= 2 && players.every((p) => p.ready);
          if (!allReady) {
            setPhase("lobby");
            setMyReady(me?.ready ?? false);
          }
        }
      });

      t.onStart(() => {
        setPhase("battle");
        setBattleStartSignal((n) => n + 1);
      });

      return () => {
        closed = true;
        t.close();
      };
    },
    [teardown],
  );

  const beginRoom = useCallback(
    (
      server: string,
      room: string,
      name: string,
      joinRole: "player" | "opponent",
    ) => {
      const code = buildDuelCode(server, room);
      setDuelCodeState(code);
      setShareUrl(buildDuelShareUrl(code));
      if (joinRole === "player") setDuelHash(code);
      wireTransport(server, room, name, joinRole);
    },
    [wireTransport],
  );

  const createRoom = useCallback(
    (name: string, fixedRoomId?: string) => {
      const server = defaultWsUrl();
      const room = fixedRoomId?.trim() || randomDuelRoomId();
      beginRoom(server, room, name, "player");
    },
    [beginRoom],
  );

  const connectToRoom = useCallback(
    (
      name: string,
      roomId: string,
      joinRole: "player" | "opponent",
      serverUrl?: string,
    ) => {
      beginRoom(serverUrl ?? defaultWsUrl(), roomId, name, joinRole);
    },
    [beginRoom],
  );

  const joinByCode = useCallback(
    (code: string, name: string) => {
      const parsed = parseDuelCode(code);
      if (!parsed) {
        setError("Неверный код комнаты или недоверенный сервер");
        return;
      }
      setDuelCodeState(code.trim());
      setShareUrl(buildDuelShareUrl(code.trim()));
      setDuelHash(code.trim());
      wireTransport(parsed.server, parsed.room, name, "opponent");
    },
    [wireTransport],
  );

  const sendReady = useCallback((ready: boolean) => {
    setMyReady(ready);
    transportRef.current?.sendReady(ready);
  }, []);

  const disconnect = useCallback(() => {
    teardown();
  }, [teardown]);

  const clearBattleStartSignal = useCallback(() => {
    setBattleStartSignal(0);
  }, []);

  useEffect(() => () => teardown(), [teardown]);

  const value = useMemo<WsSessionValue>(
    () => ({
      phase,
      wsUrl,
      roomId,
      role,
      duelCode,
      shareUrl,
      lobby,
      myReady,
      error,
      connected,
      transport,
      battleStartSignal,
      createRoom,
      connectToRoom,
      joinByCode,
      sendReady,
      disconnect,
      clearBattleStartSignal,
    }),
    [
      phase,
      wsUrl,
      roomId,
      role,
      duelCode,
      shareUrl,
      lobby,
      myReady,
      error,
      connected,
      transport,
      battleStartSignal,
      createRoom,
      connectToRoom,
      joinByCode,
      sendReady,
      disconnect,
      clearBattleStartSignal,
    ],
  );

  return (
    <WsSessionContext.Provider value={value}>{children}</WsSessionContext.Provider>
  );
}

export function useWsSession(): WsSessionValue {
  const ctx = useContext(WsSessionContext);
  if (!ctx) throw new Error("useWsSession requires WsSessionProvider");
  return ctx;
}

export function useWsSessionOptional(): WsSessionValue | null {
  return useContext(WsSessionContext);
}
