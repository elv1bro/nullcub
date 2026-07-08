import { MAX_HP, OPPONENT_MAX_HP } from "@/lib/combat";
import type { NetBattleStatePayload } from "./protocol";

function clampHp(n: unknown, max: number): number {
  if (typeof n !== "number" || !Number.isFinite(n)) return max;
  return Math.max(0, Math.min(max, Math.round(n)));
}

/**
 * Санитизация host→guest battleState.
 * P2P хост trusted — это не античит, только защита от NaN/мусора и
 * несогласованного winner при живых HP.
 */
export function sanitizeHostBattleState(
  payload: NetBattleStatePayload,
): NetBattleStatePayload {
  const playerHp = clampHp(payload.playerHp, MAX_HP);
  const opponentHp = clampHp(payload.opponentHp, OPPONENT_MAX_HP);
  const playerName =
    typeof payload.playerName === "string"
      ? payload.playerName.replace(/[\u0000-\u001f]/g, "").slice(0, 32)
      : "";
  const opponentName =
    typeof payload.opponentName === "string"
      ? payload.opponentName.replace(/[\u0000-\u001f]/g, "").slice(0, 32)
      : "";

  let battleOver = Boolean(payload.battleOver);
  let winner: NetBattleStatePayload["winner"] = null;

  if (battleOver) {
    if (payload.winner === "player" || payload.winner === "opponent") {
      winner = payload.winner;
    } else if (playerHp <= 0 && opponentHp > 0) {
      winner = "opponent";
    } else if (opponentHp <= 0 && playerHp > 0) {
      winner = "player";
    } else {
      // Оба живы или оба мертвы без явного winner — не форсим конец.
      battleOver = playerHp <= 0 || opponentHp <= 0;
      winner = null;
    }
  }

  return {
    playerHp,
    opponentHp,
    battleOver,
    winner,
    playerName,
    opponentName,
  };
}
