import { GameContext } from "@/GameContext";
import { playMenuSound } from "@/audio";
import { setBattleQuick } from "@/lib/battleConfig";
import { useWsSession } from "@/net/WsSessionContext";
import { buildDuelShareUrl } from "@/net/wsClient";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useCallback, useContext, useState } from "react";

export function WsDuelPanel() {
  const { sendN } = useContext(GameContext);
  const { profile } = usePlayerProfile();
  const ws = useWsSession();
  const [joinDraft, setJoinDraft] = useState("");
  const [copied, setCopied] = useState(false);

  const onCreate = useCallback(() => {
    playMenuSound("click");
    ws.createRoom(profile.name);
  }, [ws, profile.name]);

  const onJoin = useCallback(() => {
    playMenuSound("click");
    ws.joinByCode(joinDraft, profile.name);
  }, [ws, joinDraft, profile.name]);

  const onReadyToggle = useCallback(() => {
    playMenuSound("click");
    ws.sendReady(!ws.myReady);
  }, [ws]);

  const onCopyCode = useCallback(async () => {
    if (!ws.duelCode) return;
    const url = ws.shareUrl ?? buildDuelShareUrl(ws.duelCode);
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      await navigator.clipboard.writeText(ws.duelCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [ws.duelCode, ws.shareUrl]);

  const onLocalSolo = useCallback(() => {
    playMenuSound("play");
    setBattleQuick();
    sendN("START_BATTLE")();
  }, [sendN]);

  const allReady = ws.lobby.length >= 2 && ws.lobby.every((p) => p.ready);
  const inLobby = ws.phase === "lobby" || ws.phase === "connecting";

  if (ws.phase === "idle") {
    return (
      <div className="flex flex-col items-center gap-6 w-full max-w-md mx-auto p-4">
        <h2 className="text-lg font-bold text-white font-ui">Онлайн-дуэль</h2>
        <p className="text-sm text-gray-400 text-center">
          Создайте комнату и отправьте код другу, или введите код приглашения.
        </p>

        <button
          type="button"
          onClick={onCreate}
          className="w-full px-6 py-3 rounded-lg font-bold bg-cyan-600 text-white hover:bg-cyan-500 transition-colors"
        >
          Создать комнату
        </button>

        <div className="w-full flex flex-col gap-2">
          <label className="text-xs text-gray-500 uppercase tracking-wide">
            Код комнаты
          </label>
          <div className="flex gap-2">
            <input
              type="text"
              value={joinDraft}
              onChange={(e) => setJoinDraft(e.target.value)}
              placeholder="Вставьте код…"
              className="flex-1 px-3 py-2 rounded bg-dark-700 text-white border border-gray-600 text-sm"
            />
            <button
              type="button"
              onClick={onJoin}
              disabled={!joinDraft.trim()}
              className="px-4 py-2 rounded-lg font-bold bg-gray-600 text-white hover:bg-gray-500 disabled:opacity-40"
            >
              Войти
            </button>
          </div>
        </div>

        <div className="w-full border-t border-gray-700 pt-4">
          <button
            type="button"
            onClick={onLocalSolo}
            className="w-full px-4 py-2 rounded-lg text-sm text-gray-300 hover:text-white border border-gray-600 hover:border-gray-500"
          >
            Быстрый бой с ботом
          </button>
        </div>

        {ws.error && <p className="text-sm text-red-400">{ws.error}</p>}
      </div>
    );
  }

  if (inLobby) {
    return (
      <div className="flex flex-col items-center gap-4 w-full max-w-md mx-auto p-4">
        <h2 className="text-lg font-bold text-white font-ui">
          {ws.phase === "connecting" ? "Подключение…" : "Комната ожидания"}
        </h2>

        {ws.duelCode && (
          <div className="w-full flex flex-col gap-2 p-4 rounded-lg bg-dark-700 border border-gray-600">
            <span className="text-xs text-gray-400 uppercase">Код для друга</span>
            <code className="text-sm text-cyan-300 break-all select-all">{ws.duelCode}</code>
            <button
              type="button"
              onClick={() => void onCopyCode()}
              className="text-xs text-gray-400 hover:text-white underline self-start"
            >
              {copied ? "Скопировано ✓" : "Копировать ссылку"}
            </button>
          </div>
        )}

        <ul className="w-full flex flex-col gap-2">
          {ws.lobby.map((p) => (
            <li
              key={p.fighterId}
              className="flex items-center justify-between px-4 py-2 rounded bg-dark-700 text-white"
            >
              <span>
                {p.name}
                {p.fighterId === ws.role ? " (вы)" : ""}
              </span>
              <span className={p.ready ? "text-green-400" : "text-gray-500"}>
                {p.ready ? "готов" : "ждём…"}
              </span>
            </li>
          ))}
          {ws.lobby.length < 2 && (
            <li className="px-4 py-2 rounded bg-dark-700 text-gray-500 italic text-sm">
              Ожидание второго игрока…
            </li>
          )}
        </ul>

        {ws.phase === "lobby" && (
          <button
            type="button"
            onClick={onReadyToggle}
            className={`px-6 py-3 rounded-lg font-bold transition-colors ${
              ws.myReady
                ? "bg-green-600 text-white hover:bg-green-500"
                : "bg-gray-600 text-white hover:bg-gray-500"
            }`}
          >
            {ws.myReady ? "Готов ✓" : "Я готов"}
          </button>
        )}

        {allReady && (
          <p className="text-sm text-green-400">Все готовы — старт!</p>
        )}

        <button
          type="button"
          onClick={() => ws.disconnect()}
          className="text-xs text-gray-500 hover:text-gray-300 underline"
        >
          Покинуть комнату
        </button>

        {ws.error && <p className="text-sm text-red-400">{ws.error}</p>}
      </div>
    );
  }

  return null;
}
