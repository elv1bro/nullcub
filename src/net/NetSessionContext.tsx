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
import {
  createNetRoom,
  getRoomIdFromHash,
  randomRoomId,
  setRoomHash,
  wireNetActions,
  type NetRoom,
} from "./room";
import type { FacePrivacyMode, NetReadyPayload } from "./protocol";

interface PeerState {
  id: string;
  name: string;
  ready: boolean;
  stream: MediaStream | null;
  cam: boolean;
  mic: boolean;
  faceMode: FacePrivacyMode;
}

interface NetSessionValue {
  roomId: string | null;
  room: NetRoom | null;
  isHost: boolean;
  connected: boolean;
  connectError: string | null;
  peers: PeerState[];
  localStream: MediaStream | null;
  actions: ReturnType<typeof wireNetActions> | null;
  /** Увеличивается, когда гость получил startMatch от хоста. */
  guestStartSignal: number;
  createRoom: () => string;
  joinRoomById: (id: string) => void;
  setLocalMedia: (stream: MediaStream | null) => void;
  setPrivacy: (cam: boolean, mic: boolean, faceMode: FacePrivacyMode) => void;
  sendReady: (name: string, ready: boolean) => void;
  clearGuestStartSignal: () => void;
}

const NetSessionContext = createContext<NetSessionValue | null>(null);

export function NetSessionProvider({ children }: PropsWithChildren) {
  const [roomId, setRoomId] = useState<string | null>(() => getRoomIdFromHash());
  const [room, setRoom] = useState<NetRoom | null>(null);
  const [connected, setConnected] = useState(false);
  const [connectError, setConnectError] = useState<string | null>(null);
  const [peers, setPeers] = useState<PeerState[]>([]);
  const [localStream, setLocalStreamState] = useState<MediaStream | null>(null);
  const [isHost, setIsHost] = useState(false);
  const [guestStartSignal, setGuestStartSignal] = useState(0);
  const roomRef = useRef<NetRoom | null>(null);
  const isHostRef = useRef(false);

  const actions = useMemo(() => (room ? wireNetActions(room) : null), [room]);

  const broadcastMediaState = useCallback(
    (cam: boolean, mic: boolean, faceMode: FacePrivacyMode) => {
      if (!actions) return;
      actions.mediaState[0]({ fighterId: "local", cam, mic, faceMode });
    },
    [actions],
  );

  const connectRoom = useCallback((id: string) => {
    const trimmed = id.trim();
    if (!trimmed) return;

    try {
      void roomRef.current?.leave();
      setConnectError(null);
      setRoomId(trimmed);
      setRoomHash(trimmed);
      const instance = createNetRoom(trimmed);
      roomRef.current = instance;
      const host = Object.keys(instance.getPeers()).length === 0;
      isHostRef.current = host;
      setIsHost(host);
      setRoom(instance);
      setConnected(true);
      setPeers([]);
    } catch (err) {
      console.error("[net] connectRoom failed:", err);
      roomRef.current = null;
      setRoom(null);
      setConnected(false);
      setConnectError(err instanceof Error ? err.message : "Network connect failed");
    }
  }, []);

  useEffect(() => {
    if (!room || !actions) return;

    const [, onReady] = actions.ready;
    onReady((data: NetReadyPayload, peerId) => {
      setPeers((prev) => {
        const existing = prev.find((p) => p.id === peerId);
        if (existing) {
          return prev.map((p) =>
            p.id === peerId ? { ...p, name: data.name, ready: data.ready } : p,
          );
        }
        return [
          ...prev,
          {
            id: peerId,
            name: data.name,
            ready: data.ready,
            stream: null,
            cam: true,
            mic: true,
            faceMode: "video" as FacePrivacyMode,
          },
        ];
      });
    });

    const [, onMedia] = actions.mediaState;
    onMedia((data, peerId) => {
      setPeers((prev) =>
        prev.map((p) =>
          p.id === peerId
            ? { ...p, cam: data.cam, mic: data.mic, faceMode: data.faceMode }
            : p,
        ),
      );
    });

    room.onPeerJoin = (peerId) => {
      setPeers((prev) => [
        ...prev.filter((p) => p.id !== peerId),
        {
          id: peerId,
          name: peerId.slice(0, 6),
          ready: false,
          stream: null,
          cam: true,
          mic: true,
          faceMode: "video",
        },
      ]);
    };

    room.onPeerLeave = (peerId) => {
      setPeers((prev) => prev.filter((p) => p.id !== peerId));
    };

    room.onPeerStream = (stream, peerId) => {
      setPeers((prev) =>
        prev.map((p) => (p.id === peerId ? { ...p, stream } : p)),
      );
    };

    const [, onStartMatch] = actions.startMatch;
    onStartMatch((data) => {
      if (isHostRef.current) return;
      if (!data.roomId) return;
      setGuestStartSignal((n) => n + 1);
    });

    return () => {
      room.onPeerJoin = null;
      room.onPeerLeave = null;
      room.onPeerStream = null;
      try {
        void room.leave();
      } catch (err) {
        console.warn("[net] room.leave failed:", err);
      }
      roomRef.current = null;
    };
  }, [room, actions]);

  useEffect(() => {
    if (!room || !localStream) return;
    try {
      room.addStream(localStream);
    } catch (err) {
      console.warn("[net] addStream failed:", err);
    }
  }, [room, localStream]);

  const setLocalMedia = useCallback((stream: MediaStream | null) => {
    setLocalStreamState(stream);
  }, []);

  const setPrivacy = useCallback(
    (cam: boolean, mic: boolean, faceMode: FacePrivacyMode) => {
      localStream?.getVideoTracks().forEach((t) => {
        t.enabled = cam && faceMode === "video";
      });
      localStream?.getAudioTracks().forEach((t) => {
        t.enabled = mic;
      });
      broadcastMediaState(cam, mic, faceMode);
    },
    [localStream, broadcastMediaState],
  );

  const sendReady = useCallback(
    (name: string, ready: boolean) => {
      actions?.ready[0]({ fighterId: "local", name, ready });
    },
    [actions],
  );

  const clearGuestStartSignal = useCallback(() => {
    setGuestStartSignal(0);
  }, []);

  const createRoom = useCallback(() => {
    const id = randomRoomId();
    connectRoom(id);
    return id;
  }, [connectRoom]);

  const value = useMemo(
    (): NetSessionValue => ({
      roomId,
      room,
      isHost,
      connected,
      connectError,
      peers,
      localStream,
      actions,
      guestStartSignal,
      createRoom,
      joinRoomById: connectRoom,
      setLocalMedia,
      setPrivacy,
      sendReady,
      clearGuestStartSignal,
    }),
    [
      roomId,
      room,
      isHost,
      connected,
      connectError,
      peers,
      localStream,
      actions,
      guestStartSignal,
      createRoom,
      connectRoom,
      setLocalMedia,
      setPrivacy,
      sendReady,
      clearGuestStartSignal,
    ],
  );

  return (
    <NetSessionContext.Provider value={value}>
      {children}
    </NetSessionContext.Provider>
  );
}

export function useNetSession(): NetSessionValue {
  const ctx = useContext(NetSessionContext);
  if (!ctx) throw new Error("useNetSession requires NetSessionProvider");
  return ctx;
}
