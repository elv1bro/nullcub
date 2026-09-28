import { describe, expect, it } from "vitest";
import { GameRoom } from "./gameRoom";
import { InputRateLimiter } from "./inputValidator";

function client(id: string, name: string, role: "player" | "opponent" = "player") {
  const messages: unknown[] = [];
  return {
    id,
    name,
    fighterId: role,
    ownedFighterIds: [] as string[],
    send: (msg: unknown) => messages.push(msg),
    limiter: new InputRateLimiter(),
    messages,
  };
}

describe("GameRoom multi-slot", () => {
  it("accepts up to 4 network clients", () => {
    const room = new GameRoom({
      roomId: "test-room",
      secret: "0123456789abcdef",
      syncSettle: true,
      spawnItems: false,
    });
    const a = client("a", "A", "player");
    const b = client("b", "B", "opponent");
    const c = client("c", "C");
    const d = client("d", "D");
    expect(room.addClient(a)).toBe("player");
    expect(room.addClient(b)).toBe("opponent");
    expect(room.addClient(c)).toBe("p2");
    expect(room.addClient(d)).toBe("p3");
    expect(room.addClient(client("e", "E"))).toBeNull();
    room.destroy();
  });

  it("allows host to claim a local second slot", () => {
    const room = new GameRoom({
      roomId: "test-local",
      secret: "0123456789abcdef",
      syncSettle: true,
      spawnItems: false,
    });
    const host = client("host", "Host", "player");
    expect(room.addClient(host)).toBe("player");
    expect(room.claimLocal("host", "P2")).toBe("opponent");
    const hostClient = room.clients.get("host")!;
    expect(hostClient.ownedFighterIds).toEqual(["player", "opponent"]);
    room.destroy();
  });

  it("starts when 3 players are ready", () => {
    const room = new GameRoom({
      roomId: "test-3",
      secret: "0123456789abcdef",
      syncSettle: true,
      spawnItems: false,
    });
    const a = client("a", "A", "player");
    const b = client("b", "B", "opponent");
    const c = client("c", "C");
    room.addClient(a);
    room.addClient(b);
    room.addClient(c);
    room.setReady("a", true);
    room.setReady("b", true);
    expect(a.messages.some((m) => (m as { type: string }).type === "start")).toBe(
      false,
    );
    room.setReady("c", true);
    expect(a.messages.some((m) => (m as { type: string }).type === "start")).toBe(
      true,
    );
    room.destroy();
  });

  it("partyBots: pads to 4 allies + 1 boss and starts with 1 ready host", () => {
    const room = new GameRoom({
      roomId: "test-party-bots",
      secret: "0123456789abcdef",
      syncSettle: true,
      spawnItems: false,
    });
    const a = client("a", "Host", "player");
    const b = client("b", "Guest", "opponent");
    room.addClient(a);
    room.addClient(b);
    room.setBattleMode("partyBots", "normal");
    room.setReady("a", true);
    expect(a.messages.some((m) => (m as { type: string }).type === "start")).toBe(
      false,
    );
    room.setReady("b", true);
    const start = a.messages.find(
      (m) => (m as { type: string }).type === "start",
    ) as { type: string; fighterIds?: string[] } | undefined;
    expect(start).toBeTruthy();
    expect(start!.fighterIds).toHaveLength(5);
    expect(start!.fighterIds).toContain("bossBot");
    expect(start!.fighterIds?.filter((id) => id.startsWith("ally")).length).toBe(
      2,
    );

    type SessionView = {
      fighters: Array<{ id: string; team?: number; aiProfile?: unknown }>;
      isBattleOver: () => boolean;
    };
    const session = (room as unknown as { session: SessionView | null }).session;
    expect(session).toBeTruthy();
    expect(session!.isBattleOver()).toBe(false);
    const humans = session!.fighters.filter((f) => f.team === 0);
    const bots = session!.fighters.filter((f) => f.team === 1);
    expect(humans).toHaveLength(4);
    expect(bots).toHaveLength(1);
    expect(bots[0]!.aiProfile).toBeTruthy();
    room.destroy();
  });

  it("rejects input for foreign fighterId (falls back to owned primary)", () => {
    const room = new GameRoom({
      roomId: "test-input",
      secret: "0123456789abcdef",
      syncSettle: true,
      spawnItems: false,
    });
    const a = client("a", "A", "player");
    const b = client("b", "B", "opponent");
    room.addClient(a);
    room.addClient(b);
    room.setReady("a", true);
    room.setReady("b", true);
    // syncSettle уже beginBattle; крутим тики до конца spawn grace.
    for (let i = 0; i < 180; i++) room.tickBattle(1000 / 60);

    type SessionView = {
      getFighter: (id: string) => { input: { move: { x: number } } } | undefined;
    };
    const session = (room as unknown as { session: SessionView | null }).session;
    expect(session).toBeTruthy();

    const before = session!.getFighter("opponent")!.input.move.x;
    room.handleInput(
      "a",
      {
        seq: 1,
        t: performance.now(),
        move: { x: 1, y: 0 },
        grabL: false,
        grabR: false,
        dash: false,
        flip: false,
        freeze: false,
        reset: false,
      },
      "opponent",
    );
    // Чужой fighterId → ввод уходит на primary (player), opponent не меняется.
    expect(session!.getFighter("opponent")!.input.move.x).toBe(before);
    expect(session!.getFighter("player")!.input.move.x).toBe(1);
    room.destroy();
  });
});
