import { GameContext } from "@/GameContext";
import { useNetSession } from "@/net/NetSessionContext";
import { getRoomIdFromHash } from "@/net/room";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { playMenuSound } from "@/audio";
import {
  applyTeamBattleConfig,
  countLocalHumans,
  countRemote,
  emptyExtraSlots,
  TEAM_SIZE,
  type TeamSlot,
  type TeamSlotIndex,
} from "@/team/teamSlots";
import { useTranslation } from "@/settings/SettingsContext";
import { useCallback, useContext, useEffect, useMemo, useRef, useState, type CSSProperties } from "react";

type ExtraSlotMap = ReturnType<typeof emptyExtraSlots>;

function parseRoomId(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) return "";
  if (trimmed.includes("room=")) {
    const hashPart = trimmed.includes("#") ? trimmed.slice(trimmed.indexOf("#") + 1) : trimmed;
    const fromHash = new URLSearchParams(hashPart).get("room");
    if (fromHash) return fromHash;
  }
  return trimmed.split("/").pop()?.split("#")[0]?.split("?")[0] ?? trimmed;
}

function buildSlots(
  profileName: string,
  extras: ExtraSlotMap,
  peers: { id: string; name: string }[],
): TeamSlot[] {
  const slots: TeamSlot[] = [
    { kind: "you", name: profileName },
    { ...extras[2] },
    { ...extras[3] },
    { ...extras[4] },
  ];

  for (let i = 1; i < TEAM_SIZE; i++) {
    const slot = slots[i]!;
    if (slot.kind === "remote" && !peers.some((p) => p.id === slot.peerId)) {
      slots[i] = { kind: "empty" };
    }
  }

  const usedPeers = new Set(
    slots
      .filter((s): s is Extract<TeamSlot, { kind: "remote" }> => s.kind === "remote")
      .map((s) => s.peerId),
  );

  for (const peer of peers) {
    if (usedPeers.has(peer.id)) continue;
    const emptyIndex = slots.findIndex((s, idx) => idx > 0 && s.kind === "empty");
    if (emptyIndex < 0) break;
    slots[emptyIndex] = { kind: "remote", peerId: peer.id, name: peer.name };
    usedPeers.add(peer.id);
  }

  return slots;
}

function slotInitial(name: string): string {
  const ch = name.trim()[0];
  return ch ? ch.toUpperCase() : "?";
}

export function TeamLobbyPanel() {
  const { sendN } = useContext(GameContext);
  const t = useTranslation();
  const { profile } = usePlayerProfile();
  const {
    connected,
    roomId,
    isHost,
    peers,
    actions,
    createRoom,
    joinRoomById,
    setLocalMedia,
    setPrivacy,
    sendReady,
    connectError,
  } = useNetSession();
  const roomBootstrappedRef = useRef(false);
  const [extras, setExtras] = useState<ExtraSlotMap>(emptyExtraSlots);
  const [openSlot, setOpenSlot] = useState<TeamSlotIndex | null>(null);
  const [joinDraft, setJoinDraft] = useState("");
  const [copied, setCopied] = useState(false);
  const [ready, setReady] = useState(false);
  const [camOn, setCamOn] = useState(true);
  const [micOn, setMicOn] = useState(true);
  const [faceMode, setFaceMode] = useState<"video" | "tracking" | "none">("video");

  const hashRoom = getRoomIdFromHash();
  const playerColor = profile.colors.main;
  const playerAccent = profile.colors.secondary;

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
        setLocalMedia(stream);
        setPrivacy(camOn, micOn, faceMode);
      } catch {
        if (!cancelled) setPrivacy(false, false, "none");
      }
    })();
    return () => {
      cancelled = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- init media once
  }, [setLocalMedia, setPrivacy]);

  useEffect(() => {
    setPrivacy(camOn, micOn, faceMode);
  }, [camOn, micOn, faceMode, setPrivacy]);

  useEffect(() => {
    if (roomBootstrappedRef.current || connected) return;
    if (!hashRoom) return;
    roomBootstrappedRef.current = true;
    joinRoomById(hashRoom);
  }, [hashRoom, connected, joinRoomById]);

  const ensureRoom = useCallback(() => {
    if (connected && roomId) return roomId;
    if (hashRoom) {
      joinRoomById(hashRoom);
      return hashRoom;
    }
    return createRoom();
  }, [connected, roomId, hashRoom, createRoom, joinRoomById]);

  const isOnlineGuest = connected && !isHost;
  const showReady = connected && (isOnlineGuest || (isHost && peers.length > 0));

  useEffect(() => {
    if (!showReady) return;
    sendReady(profile.name, ready);
  }, [ready, profile.name, sendReady, showReady]);

  const slots = useMemo(
    () => buildSlots(profile.name, extras, peers),
    [profile.name, extras, peers],
  );

  const roomLink = roomId
    ? `${window.location.origin}${window.location.pathname}#room=${roomId}`
    : "";

  const remoteCount = countRemote(slots);
  const localHumanCount = countLocalHumans(slots);
  const filledExtras = slots.slice(1).filter((s) => s.kind !== "empty").length;
  const onlineMatch = remoteCount > 0 || peers.length > 0;

  const canStart = isOnlineGuest
    ? false
    : onlineMatch && connected
      ? isHost && peers.length > 0 && peers.some((p) => p.ready)
      : true;

  const copyLink = useCallback(async () => {
    ensureRoom();
    playMenuSound("click");
    const link =
      roomLink ||
      (roomId
        ? `${window.location.origin}${window.location.pathname}#room=${roomId}`
        : "");
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setJoinDraft(link);
    }
  }, [ensureRoom, roomLink, roomId]);

  const addLocal = (index: TeamSlotIndex) => {
    if (index === 1) return;
    playMenuSound("click");
    setExtras((prev) => ({
      ...prev,
      [index]: {
        kind: "local",
        name: t.team.localPlayer.replace("{n}", String(index)),
        seat: index,
      },
    }));
    setOpenSlot(null);
  };

  const clearSlot = (index: TeamSlotIndex) => {
    if (index === 1) return;
    playMenuSound("click");
    setExtras((prev) => ({ ...prev, [index]: { kind: "empty" } }));
    setOpenSlot(null);
  };

  const joinByCode = () => {
    const id = parseRoomId(joinDraft);
    if (!id) return;
    playMenuSound("click");
    joinRoomById(id);
    setOpenSlot(null);
  };

  const onStart = () => {
    if (!canStart) return;
    playMenuSound("play");
    const activeRoomId = onlineMatch ? ensureRoom() : roomId;
    applyTeamBattleConfig({
      slots,
      remoteCount,
      localHumanCount,
      roomId: activeRoomId,
      isHost: onlineMatch ? isHost || !connected : true,
    });
    if (onlineMatch && actions && isHost && activeRoomId) {
      const payload = { roomId: activeRoomId };
      actions.startMatch[0](payload, []);
      window.setTimeout(() => actions.startMatch[0](payload, []), 400);
      window.setTimeout(() => actions.startMatch[0](payload, []), 1200);
    }
    sendN("START_BATTLE")();
  };

  const slotLabel = (_index: TeamSlotIndex, slot: TeamSlot) => {
    if (slot.kind === "you") return slot.name;
    if (slot.kind === "local") return slot.name;
    if (slot.kind === "remote") return slot.name;
    return t.team.emptySlot;
  };

  const slotBadge = (slot: TeamSlot) => {
    if (slot.kind === "you") return t.team.badgeYou;
    if (slot.kind === "local") return t.team.badgeLocal;
    if (slot.kind === "remote") return t.team.badgeOnline;
    return null;
  };

  const statusHint =
    remoteCount > 0
      ? t.team.onlineHint
          .replace("{count}", String(peers.length))
          .replace("{max}", String(TEAM_SIZE - 1))
      : filledExtras > 0
        ? t.team.localControlsHint
        : t.team.soloHint;

  const startLabel = isOnlineGuest
    ? t.team.waitHost
    : onlineMatch && connected && isHost
      ? t.team.startOnline
      : t.team.start;

  return (
    <div
      className="team-lobby"
      style={
        {
          "--team-player": playerColor,
          "--team-player-accent": playerAccent,
        } as CSSProperties
      }
    >
      {connectError && (
        <p className="team-lobby__error">{connectError}</p>
      )}

      <p className="team-lobby__hint font-ui">{t.team.hint}</p>

      <div className="team-lobby__grid">
        {slots.map((slot, idx) => {
          const index = (idx + 1) as TeamSlotIndex;
          const filled = slot.kind !== "empty";
          const badge = slotBadge(slot);
          const isYou = slot.kind === "you";

          return (
            <button
              key={index}
              type="button"
              className={[
                "team-slot",
                filled ? "team-slot--filled" : "team-slot--empty",
                isYou ? "team-slot--you" : "",
                openSlot === index ? "team-slot--active" : "",
              ]
                .filter(Boolean)
                .join(" ")}
              onClick={() => {
                if (filled || index === 1) return;
                playMenuSound("click");
                setOpenSlot(openSlot === index ? null : index);
              }}
              disabled={filled && index > 1 && slot.kind !== "local"}
              aria-label={
                filled
                  ? slotLabel(index, slot)
                  : t.team.addPlayer
              }
            >
              <span className="team-slot__num">{index}</span>
              {filled ? (
                <>
                  <span className="team-slot__avatar" aria-hidden>
                    {slotInitial(slotLabel(index, slot))}
                  </span>
                  <span className="team-slot__name">{slotLabel(index, slot)}</span>
                  {badge && <span className="team-slot__badge">{badge}</span>}
                  {index > 1 && slot.kind === "local" && (
                    <span
                      role="button"
                      tabIndex={0}
                      className="team-slot__clear"
                      onClick={(e) => {
                        e.stopPropagation();
                        clearSlot(index);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          e.stopPropagation();
                          clearSlot(index);
                        }
                      }}
                      aria-label={t.team.remove}
                    >
                      ×
                    </span>
                  )}
                </>
              ) : (
                <span className="team-slot__add">+</span>
              )}
            </button>
          );
        })}
      </div>

      {openSlot !== null && slots[openSlot - 1]?.kind === "empty" && (
        <div className="team-lobby__invite menu-panel-enter">
          <p className="team-lobby__invite-title">
            {t.team.slotInvite.replace("{n}", String(openSlot))}
          </p>
          <div className="team-lobby__invite-actions">
            <button type="button" className="menu-nav-btn text-sm!" onClick={copyLink}>
              {copied ? t.team.linkCopied : t.team.copyLink}
            </button>
            {!isOnlineGuest && (
              <button
                type="button"
                className="menu-nav-btn text-sm!"
                onClick={() => addLocal(openSlot)}
              >
                {t.team.addLocal}
              </button>
            )}
          </div>
          {isOnlineGuest && (
            <div className="team-lobby__join-row">
              <input
                className="team-lobby__join-input"
                placeholder={t.team.pasteLink}
                value={joinDraft}
                onChange={(e) => setJoinDraft(e.target.value)}
              />
              <button type="button" className="menu-nav-btn text-xs!" onClick={joinByCode}>
                {t.multiplayer.join}
              </button>
            </div>
          )}
          {roomLink && (
            <p className="team-lobby__link-preview">{roomLink}</p>
          )}
        </div>
      )}

      <p className="team-lobby__status">{statusHint}</p>

      <div className="team-lobby__media">
        <span className="team-lobby__media-label">{t.team.mediaLabel}</span>
        <div className="team-lobby__media-toggles">
          <label className="team-pill">
            <input type="checkbox" checked={camOn} onChange={(e) => setCamOn(e.target.checked)} />
            {t.multiplayer.cam}
          </label>
          <label className="team-pill">
            <input type="checkbox" checked={micOn} onChange={(e) => setMicOn(e.target.checked)} />
            {t.multiplayer.mic}
          </label>
          <select
            className="team-pill team-pill--select"
            value={faceMode}
            onChange={(e) => setFaceMode(e.target.value as "video" | "tracking" | "none")}
          >
            <option value="video">{t.multiplayer.faceVideo}</option>
            <option value="tracking">{t.multiplayer.faceTracking}</option>
            <option value="none">{t.multiplayer.faceNone}</option>
          </select>
        </div>
      </div>

      <div className="team-lobby__footer">
        {showReady && (
          <button
            type="button"
            className={`menu-nav-btn team-lobby__ready${ready ? " team-lobby__ready--on" : ""}`}
            onClick={() => setReady((r) => !r)}
          >
            {ready ? t.multiplayer.readyOn : t.multiplayer.readyOff}
          </button>
        )}

        <button
          type="button"
          className="menu-nav-btn menu-nav-btn--primary team-lobby__start"
          disabled={!canStart}
          onClick={onStart}
        >
          {startLabel}
        </button>
      </div>
    </div>
  );
}
