import type { GameRoomDebugInfo } from "@/server/debugTypes";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { RagdollDevConfig, RagdollDevStats } from "./ragdollDev";

function useDevConfig() {
  const [config, setConfig] = useState<RagdollDevConfig | null>(null);
  useEffect(() => {
    window.ragdollDev?.getConfig().then(setConfig).catch(() => setConfig(null));
  }, []);
  return config;
}

function useServerStats(enabled: boolean) {
  const [stats, setStats] = useState<RagdollDevStats | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    const poll = async () => {
      try {
        const next = await window.ragdollDev?.getServerStats();
        if (alive && next) setStats(next);
      } catch {
        /* ignore */
      }
    };
    poll();
    const timer = setInterval(poll, 500);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [enabled]);
  return stats;
}

function RoomPanel({ room }: { room: GameRoomDebugInfo }) {
  return (
    <div className="rounded border border-gray-700 bg-dark-800 p-3 text-xs font-mono">
      <div className="flex justify-between gap-2 mb-2">
        <span className="text-white font-bold">{room.roomId}</span>
        <span className={room.battleStarted ? "text-green-400" : "text-yellow-400"}>
          {room.battleStarted ? (room.battleOver ? "battle · over" : "battle") : "lobby"}
        </span>
      </div>
      <ul className="mb-2 space-y-1">
        {room.players.map((p) => (
          <li key={p.fighterId} className="flex justify-between text-gray-300">
            <span>
              {p.name} ({p.fighterId})
            </span>
            <span className={p.ready ? "text-green-400" : "text-gray-500"}>
              {p.ready ? "ready" : "wait"}
            </span>
          </li>
        ))}
        {room.players.length === 0 && (
          <li className="text-gray-500 italic">нет игроков</li>
        )}
      </ul>
      {room.battleStarted && (
        <p className="text-gray-400 mb-2">
          HP player={room.playerHp ?? "—"} · opponent={room.opponentHp ?? "—"}
        </p>
      )}
      {room.events.length > 0 && (
        <div className="max-h-24 overflow-y-auto border-t border-gray-700 pt-2 text-gray-500">
          {room.events.slice(-8).map((line, i) => (
            <div key={`${line}-${i}`}>{line}</div>
          ))}
        </div>
      )}
    </div>
  );
}

export function DevHubShell() {
  const config = useDevConfig();
  const stats = useServerStats(Boolean(window.ragdollDev));
  const [copied, setCopied] = useState(false);

  const params = useMemo(() => new URLSearchParams(window.location.search), []);
  const room = config?.room ?? params.get("room") ?? "dev";
  const wsPort = config?.wsPort ?? Number(params.get("wsPort") ?? 8787);
  const hostUrl =
    config?.hostJoinUrl ??
    `http://127.0.0.1:5199/?devHub=host&room=${room}&wsPort=${wsPort}&server=ws://127.0.0.1:${wsPort}&joinName=Host`;
  const guestUrl =
    config?.guestJoinUrl ??
    `http://127.0.0.1:5199/?devHub=guest&room=${room}&wsPort=${wsPort}&server=ws://127.0.0.1:${wsPort}&joinName=Guest`;

  const onCopyGuest = useCallback(async () => {
    if (window.ragdollDev) {
      await window.ragdollDev.copyGuestUrl();
    } else {
      await navigator.clipboard.writeText(guestUrl);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, [guestUrl]);

  const onOpenGuest = useCallback(async () => {
    if (window.ragdollDev) {
      await window.ragdollDev.openGuestWindow();
      return;
    }
    window.open(guestUrl, "_blank", "noopener,noreferrer");
  }, [guestUrl]);

  return (
    <div className="h-100vh flex flex-col bg-dark-900 text-white overflow-hidden">
      <header className="shrink-0 flex items-center justify-between gap-4 px-4 py-2 border-b border-gray-700 bg-dark-800">
        <div>
          <h1 className="text-sm font-bold tracking-wide">Ragdoll Dev Hub</h1>
          <p className="text-xs text-gray-400">
            WS :{wsPort} · room <span className="text-white">{room}</span>
            {stats?.wsRunning ? " · server ok" : " · server…"}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onCopyGuest}
            className="px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-xs"
          >
            {copied ? "Скопировано ✓" : "URL гостя"}
          </button>
          <button
            type="button"
            onClick={onOpenGuest}
            className="px-3 py-1.5 rounded bg-blue-700 hover:bg-blue-600 text-xs font-semibold"
          >
            Окно гостя
          </button>
        </div>
      </header>

      <div className="flex-1 min-h-0 grid grid-cols-[320px_1fr]">
        <aside className="overflow-y-auto border-r border-gray-700 p-3 space-y-3 bg-dark-800">
          <section>
            <h2 className="text-xs uppercase tracking-wider text-gray-500 mb-2">
              Сервер
            </h2>
            <dl className="text-xs space-y-1 font-mono text-gray-300">
              <div className="flex justify-between">
                <dt>Комнат</dt>
                <dd>{stats?.roomCount ?? 0}</dd>
              </div>
              <div className="flex justify-between">
                <dt>WS</dt>
                <dd>{stats?.wsRunning ? "running" : "offline"}</dd>
              </div>
            </dl>
          </section>

          <section>
            <h2 className="text-xs uppercase tracking-wider text-gray-500 mb-2">
              Комнаты
            </h2>
            <div className="space-y-2">
              {stats?.rooms.map((r) => (
                <RoomPanel key={r.roomId} room={r} />
              ))}
              {!stats?.rooms.length && (
                <p className="text-xs text-gray-500 italic">
                  Подключите хоста — комната появится после join
                </p>
              )}
            </div>
          </section>

          <section>
            <h2 className="text-xs uppercase tracking-wider text-gray-500 mb-2">
              Как тестировать
            </h2>
            <ol className="text-xs text-gray-400 space-y-2 list-decimal list-inside">
              <li>Справа — полное меню игры, лобби внутри панели</li>
              <li>Хост — «Я готов»</li>
              <li>
                <code className="text-gray-300">yarn electron:client</code> или
                «Окно гостя»
              </li>
              <li>Гость — «Я готов» → бой</li>
            </ol>
          </section>

          <section className="text-[10px] text-gray-600 break-all">
            <p className="mb-1">Host URL:</p>
            <p>{hostUrl}</p>
            <p className="mt-2 mb-1">Guest URL:</p>
            <p>{guestUrl}</p>
          </section>
        </aside>

        <main className="min-h-0 relative bg-black">
          <iframe
            title="Host game"
            src={hostUrl}
            className="absolute inset-0 w-full h-full border-0"
            allow="camera; microphone"
          />
          <div className="absolute top-2 left-2 px-2 py-1 rounded bg-dark-900/80 text-[10px] text-gray-400 pointer-events-none">
            HOST · меню + лобби
          </div>
        </main>
      </div>
    </div>
  );
}
