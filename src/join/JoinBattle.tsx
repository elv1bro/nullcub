import { DedicatedBattleView } from "@/routes/DedicatedBattleView";
import {
  buildWsUrl,
  parseJoinHash,
  WsNetTransport,
} from "@/net/wsClient";
import type { WsLobbyPlayer } from "@/net/transport";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

type Phase = "connecting" | "lobby" | "battle";

/** Standalone join-клиент (join.html / Electron guest). */
export function JoinBattle() {
  const { profile } = usePlayerProfile();
  const joinParams = useMemo(() => parseJoinHash(), []);

  const [phase, setPhase] = useState<Phase>("connecting");
  const [statusError, setStatusError] = useState<string | null>(null);
  const [lobby, setLobby] = useState<WsLobbyPlayer[]>([]);
  const [myReady, setMyReady] = useState(false);
  const [fighterRole, setFighterRole] = useState<string>(
    joinParams.role ?? "opponent",
  );
  const [transport, setTransport] = useState<WsNetTransport | null>(null);

  const fighterRoleRef = useRef(fighterRole);
  fighterRoleRef.current = fighterRole;
  const profileNameRef = useRef(profile.name);
  profileNameRef.current = profile.name;

  useEffect(() => {
    const server = joinParams.server ?? "ws://127.0.0.1:8787";
    const room = joinParams.room;
    const secret = joinParams.secret;
    if (!room || room === "default" || !secret) {
      setStatusError("Нужны room и secret в hash (#room=…&secret=…)");
      return;
    }
    const url = buildWsUrl(server, room);
    let closed = false;

    const t = new WsNetTransport(
      url,
      (welcome) => {
        fighterRoleRef.current = welcome.role;
        setFighterRole(welcome.role);
        setPhase((p) => (p === "connecting" ? "lobby" : p));
      },
      (err) => setStatusError(err),
    );
    setTransport(t);

    t.onOpen(() => {
      if (closed) return;
      t.join(
        room,
        joinParams.name ?? profileNameRef.current,
        secret,
        joinParams.role ?? undefined,
      );
    });

    const offLobby = t.onLobby((players) => {
      setLobby(players);
      const me = players.find((p) => p.fighterId === fighterRoleRef.current);
      if (me) setMyReady(me.ready);
    });

    const offStart = t.onStart(() => {
      setPhase("battle");
    });

    return () => {
      closed = true;
      offLobby();
      offStart();
      t.close();
      setTransport(null);
    };
  }, [
    joinParams.name,
    joinParams.room,
    joinParams.role,
    joinParams.server,
    joinParams.secret,
  ]);

  const onReadyToggle = useCallback(() => {
    const next = !myReady;
    setMyReady(next);
    transport?.sendReady(next);
  }, [myReady, transport]);

  const allReady = lobby.length >= 2 && lobby.every((p) => p.ready);

  if (phase === "battle" && transport) {
    return (
      <>
        <div className="fixed top-2 right-2 z-30 text-xs text-gray-400 font-ui pointer-events-none">
          JOIN · battle
        </div>
        <DedicatedBattleView
          transport={transport}
          fighterRole={fighterRole === "player" ? "player" : "opponent"}
        />
      </>
    );
  }

  return (
    <>
      <div className="fixed top-2 right-2 z-30 text-xs text-gray-400 font-ui pointer-events-none">
        JOIN · {phase}
        {statusError ? ` · ${statusError}` : ""}
      </div>

      <div className="fixed inset-0 z-40 flex items-center justify-center bg-dark-900/90">
        <div className="flex flex-col items-center gap-6 p-8 rounded-xl border border-gray-700 bg-dark-800 min-w-80">
          <h1 className="text-xl font-bold text-white">
            {phase === "connecting" ? "Подключение…" : "Комната ожидания"}
          </h1>
          {phase === "lobby" && (
            <p className="text-sm text-gray-400">
              Вы — {fighterRole === "player" ? "игрок слева" : "гость справа"}
            </p>
          )}

          {phase === "lobby" && (
            <>
              <ul className="w-full flex flex-col gap-2">
                {lobby.map((p) => (
                  <li
                    key={p.fighterId}
                    className="flex items-center justify-between px-4 py-2 rounded bg-dark-700 text-white"
                  >
                    <span>
                      {p.name}
                      {p.fighterId === fighterRole ? " (вы)" : ""}
                    </span>
                    <span className={p.ready ? "text-green-400" : "text-gray-500"}>
                      {p.ready ? "готов" : "ждём…"}
                    </span>
                  </li>
                ))}
                {lobby.length < 2 && (
                  <li className="px-4 py-2 rounded bg-dark-700 text-gray-500 italic">
                    ожидание второго игрока…
                  </li>
                )}
              </ul>

              <button
                type="button"
                onClick={onReadyToggle}
                className={`px-6 py-3 rounded-lg font-bold transition-colors ${
                  myReady
                    ? "bg-green-600 text-white hover:bg-green-500"
                    : "bg-gray-600 text-white hover:bg-gray-500"
                }`}
              >
                {myReady ? "Готов ✓" : "Я готов"}
              </button>

              {allReady && (
                <p className="text-sm text-green-400">Все готовы — старт!</p>
              )}
            </>
          )}
        </div>
      </div>
    </>
  );
}
