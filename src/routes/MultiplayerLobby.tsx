import { GameContext } from "@/GameContext";
import { SubMenuScreen } from "@/components/menu/SubMenuScreen";
import { useNetSession } from "@/net/NetSessionContext";
import { setBattleNetwork } from "@/lib/battleConfig";
import { ENABLE_P2P } from "@/lib/featureFlags";
import { useTranslation } from "@/settings/SettingsContext";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useContext, useEffect, useState } from "react";
import { BattleUnavailable } from "./BattleUnavailable";

export default MultiplayerLobby;

export function MultiplayerLobby() {
  if (!ENABLE_P2P) {
    return (
      <BattleUnavailable reason="P2P-лобби отключено. Онлайн-дуэль — через WS в Quick Battle. Флаг: VITE_ENABLE_P2P=1." />
    );
  }
  return <MultiplayerLobbyActive />;
}

function MultiplayerLobbyActive() {
  const { sendN } = useContext(GameContext);
  const t = useTranslation();
  const { profile } = usePlayerProfile();
  const net = useNetSession();
  const [joinId, setJoinId] = useState("");
  const [roomLink, setRoomLink] = useState("");
  const [ready, setReady] = useState(false);
  const [faceMode, setFaceMode] = useState<"video" | "tracking" | "none">("video");
  const [camOn, setCamOn] = useState(true);
  const [micOn, setMicOn] = useState(true);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let cancelled = false;
    void (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { width: 640, height: 480, frameRate: 15 },
          audio: true,
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        net.setLocalMedia(stream);
        net.setPrivacy(camOn, micOn, faceMode);
      } catch {
        if (!cancelled) net.setPrivacy(false, false, "none");
      }
    })();
    return () => {
      cancelled = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  useEffect(() => {
    net.setPrivacy(camOn, micOn, faceMode);
  }, [camOn, micOn, faceMode, net]);

  useEffect(() => {
    net.sendReady(profile.name, ready);
  }, [ready, profile.name, net]);

  const onCreate = () => {
    const id = net.createRoom();
    setRoomLink(`${window.location.origin}${window.location.pathname}#room=${id}`);
  };

  const onJoin = () => {
    if (!joinId.trim()) return;
    net.joinRoomById(joinId.trim());
  };

  const onStart = () => {
    if (!net.roomId) return;
    setBattleNetwork(net.roomId, net.isHost ? "host" : "guest");
    sendN("START_BATTLE")();
  };

  return (
    <SubMenuScreen title={t.playScope.multiplayer}>
      <ul className="vstack gap-3">
        <li>
          <button type="button" className="menu-nav-btn" onClick={onCreate}>
            {t.multiplayer.createRoom}
          </button>
        </li>
        {roomLink && (
          <li className="text-xs text-gray-400 break-all text-center">{roomLink}</li>
        )}
        <li className="flex gap-2">
          <input
            className="flex-1 px-2 py-1 rounded bg-black/40 border border-gray-700"
            placeholder={t.multiplayer.roomId}
            value={joinId}
            onChange={(e) => setJoinId(e.target.value)}
          />
          <button type="button" className="menu-nav-btn text-sm!" onClick={onJoin}>
            {t.multiplayer.join}
          </button>
        </li>
        <li className="flex flex-wrap gap-2 justify-center text-sm">
          <label className="flex items-center gap-1">
            <input type="checkbox" checked={camOn} onChange={(e) => setCamOn(e.target.checked)} />
            {t.multiplayer.cam}
          </label>
          <label className="flex items-center gap-1">
            <input type="checkbox" checked={micOn} onChange={(e) => setMicOn(e.target.checked)} />
            {t.multiplayer.mic}
          </label>
          <select
            className="bg-black/40 border border-gray-700 rounded px-2"
            value={faceMode}
            onChange={(e) =>
              setFaceMode(e.target.value as "video" | "tracking" | "none")
            }
          >
            <option value="video">{t.multiplayer.faceVideo}</option>
            <option value="tracking">{t.multiplayer.faceTracking}</option>
            <option value="none">{t.multiplayer.faceNone}</option>
          </select>
        </li>
        <li>
          <button
            type="button"
            className="menu-nav-btn"
            onClick={() => setReady((r) => !r)}
          >
            {ready ? t.multiplayer.readyOn : t.multiplayer.readyOff}
          </button>
        </li>
        <li>
          <button
            type="button"
            className="menu-nav-btn"
            disabled={!net.connected || !net.isHost}
            onClick={onStart}
          >
            {t.multiplayer.start}
          </button>
        </li>
        <li>
          <button type="button" className="menu-nav-btn" onClick={sendN("BACK")}>
            {t.common.back}
          </button>
        </li>
      </ul>
    </SubMenuScreen>
  );
}
