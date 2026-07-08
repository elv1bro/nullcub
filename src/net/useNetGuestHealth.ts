import { createPopup, type HitPopup } from "@/lib/hitPopups";
import { OPPONENT_COLORS } from "@/lib/fighterColors";
import { MAX_HP } from "@/lib/combat";
import { useNetSession } from "./NetSessionContext";
import type { NetBattleStatePayload, NetHitPayload } from "./protocol";
import { useEffect, useRef, useState, type MutableRefObject } from "react";
import Matter from "matter-js";

const ARENA_SIZE = 1000;

export interface NetGuestHealthView {
  playerHp: number;
  opponentHp: number;
  battleOver: boolean;
  winner: "player" | "opponent" | null;
  playerName: string;
  opponentName: string;
  popupsRef: MutableRefObject<HitPopup[]>;
  lastHit: "player" | "opponent" | null;
}

const GUEST_BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: ARENA_SIZE, y: ARENA_SIZE },
]);

/** HUD гостя из battleState + hit-событий хоста. */
export function useNetGuestHealth(
  enabled: boolean,
  formatDamage: (amount: number) => string,
): NetGuestHealthView {
  const net = useNetSession();
  const popupsRef = useRef<HitPopup[]>([]);
  const popupSlotRef = useRef(0);
  const [playerHp, setPlayerHp] = useState(MAX_HP);
  const [opponentHp, setOpponentHp] = useState(MAX_HP);
  const [battleOver, setBattleOver] = useState(false);
  const [winner, setWinner] = useState<"player" | "opponent" | null>(null);
  const [playerName, setPlayerName] = useState("");
  const [opponentName, setOpponentName] = useState("");
  const [lastHit, setLastHit] = useState<"player" | "opponent" | null>(null);

  useEffect(() => {
    if (!enabled || !net.actions) return;
    const [, onBattleState] = net.actions.battleState;
    const [, onHit] = net.actions.hit;

    onBattleState((payload: NetBattleStatePayload) => {
      setPlayerHp(payload.opponentHp);
      setOpponentHp(payload.playerHp);
      setBattleOver(payload.battleOver);
      setPlayerName(payload.opponentName);
      setOpponentName(payload.playerName);
      if (payload.battleOver) {
        setWinner(
          payload.winner === "player"
            ? "opponent"
            : payload.winner === "opponent"
              ? "player"
              : null,
        );
      } else {
        setWinner(null);
      }
    });

    onHit((payload: NetHitPayload) => {
      const side: "player" | "opponent" =
        payload.victimId === "opponent" ? "player" : "opponent";
      setLastHit(side);
      const now = performance.now();
      popupsRef.current.push(
        createPopup(
          payload.damage,
          formatDamage(payload.damage),
          payload.x,
          payload.y,
          now,
          side,
          side === "player" ? OPPONENT_COLORS : { main: "#333", secondary: "#666" },
          popupSlotRef.current++,
          GUEST_BOUNDS,
        ),
      );
    });
  }, [enabled, net.actions, formatDamage]);

  return {
    playerHp,
    opponentHp,
    battleOver,
    winner,
    playerName,
    opponentName,
    popupsRef,
    lastHit,
  };
}
