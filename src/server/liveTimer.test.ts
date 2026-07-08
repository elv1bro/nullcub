import Matter from "matter-js";
import { afterEach, describe, expect, it, vi } from "vitest";
import { GameRoom } from "./gameRoom";
import { InputRateLimiter } from "./inputValidator";

function startRoom() {
  const room = new GameRoom({ roomId: "live-sim", secret: "c".repeat(16) });
  room.addClient({
    id: "p",
    name: "Host",
    fighterId: "player",
    send: () => {},
    limiter: new InputRateLimiter(),
  });
  room.addClient({
    id: "o",
    name: "Guest",
    fighterId: "opponent",
    send: () => {},
    limiter: new InputRateLimiter(),
  });
  room.setReady("p", true);
  room.setReady("o", true);
  return room;
}

function getSession(room: GameRoom) {
  return (room as unknown as { session: import("@/core/battleSession").BattleSession })
    .session;
}

describe("GameRoom live timers", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("tracks HP over 15s with real setInterval like production server", async () => {
    vi.useFakeTimers();
    const room = startRoom();
    const session = getSession(room);
    const log: string[] = [];

    const poll = setInterval(() => {
      const ph = session.getHp("player");
      const oh = session.getHp("opponent");
      let maxV = 0;
      for (const b of Matter.Composite.allBodies(session.engine.world)) {
        if (!b.isStatic) maxV = Math.max(maxV, Matter.Vector.magnitude(b.velocity));
      }
      log.push(
        `t=${(log.length * 0.5).toFixed(1)}s player=${ph.toFixed(0)} guest=${oh.toFixed(0)} v=${maxV.toFixed(1)}`,
      );
      if (oh <= 0 || ph <= 0) {
        clearInterval(poll);
      }
    }, 500);

    await vi.advanceTimersByTimeAsync(15_000);
    clearInterval(poll);

    const ph = session.getHp("player");
    const oh = session.getHp("opponent");
    console.log(log.join("\n"));
    console.log("FINAL", { ph, oh, battleOver: session.isBattleOver() });

    room.destroy();
    expect(oh, log.join(" | ")).toBeGreaterThan(0);
    expect(ph).toBeGreaterThan(0);
  }, 30_000);
});
