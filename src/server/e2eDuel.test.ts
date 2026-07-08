import { afterAll, beforeAll, describe, expect, it } from "vitest";
import Matter from "matter-js";
import { WebSocket } from "ws";
import { GameRoom } from "./gameRoom";
import { InputRateLimiter } from "./inputValidator";
import { emptyInput } from "@/core";
import { OPPONENT_MAX_HP } from "@/lib/combat";
import { startGameServer } from "./main";

describe("GameRoom", () => {
  it("waits for ready before starting and then accepts input", () => {
    const room = new GameRoom({ roomId: "test" });
    const sentA: unknown[] = [];
    const sentB: unknown[] = [];

    room.addClient({
      id: "a",
      name: "A",
      fighterId: "player",
      send: (msg) => sentA.push(msg),
      limiter: new InputRateLimiter(),
    });
    room.addClient({
      id: "b",
      name: "B",
      fighterId: "opponent",
      send: (msg) => sentB.push(msg),
      limiter: new InputRateLimiter(),
    });

    // до ready — только lobby-сообщения, боя нет
    expect(
      sentA.some((m) => (m as { type?: string }).type === "start"),
    ).toBe(false);
    expect(
      sentA.some((m) => (m as { type?: string }).type === "lobby"),
    ).toBe(true);

    room.setReady("a", true);
    expect(
      sentA.some((m) => (m as { type?: string }).type === "start"),
    ).toBe(false);

    room.setReady("b", true);
    expect(
      sentA.some((m) => (m as { type?: string }).type === "start"),
    ).toBe(true);
    expect(
      sentB.some((m) => (m as { type?: string }).type === "start"),
    ).toBe(true);

    room.handleInput("a", { ...emptyInput(), move: { x: 1, y: 0 } });
    room.destroy();
  });

  it("does not duplicate bodies in the physics world at battle start", () => {
    const room = new GameRoom({ roomId: "dup-bodies" });
    room.addClient({
      id: "a",
      name: "A",
      fighterId: "player",
      send: () => {},
      limiter: new InputRateLimiter(),
    });
    room.addClient({
      id: "b",
      name: "B",
      fighterId: "opponent",
      send: () => {},
      limiter: new InputRateLimiter(),
    });
    room.setReady("a", true);
    room.setReady("b", true);

    const session = (
      room as unknown as {
        session: { engine: Matter.Engine; tick: (dt: number) => void };
      }
    ).session;
    const worldBodies = Matter.Composite.allBodies(session.engine.world);
    const dynamic = worldBodies.filter((b) => !b.isStatic);
    const ordered = (room as unknown as { orderedBodies: Matter.Body[] }).orderedBodies;

    expect(dynamic.length).toBe(ordered.length);
    expect(dynamic.length).toBeGreaterThan(0);

    for (let i = 0; i < 30; i++) {
      session.tick(1000 / 60);
    }
    expect(
      (room as unknown as { session: { getHp: (id: "opponent") => number } }).session.getHp(
        "opponent",
      ),
    ).toBe(OPPONENT_MAX_HP);

    room.destroy();
  });
});

describe("WS duel e2e", () => {
  const port = 8791;
  let wss: ReturnType<typeof startGameServer>;

  beforeAll(async () => {
    wss = startGameServer(port);
    await new Promise((r) => setTimeout(r, 100));
  });

  afterAll(async () => {
    await new Promise<void>((resolve) => wss.close(() => resolve()));
  });

  it("lobby → ready → start → snapshots for both clients", async () => {
    const joinClient = (room: string, role: "player" | "opponent") =>
      new Promise<{
        welcome: boolean;
        lobby: boolean;
        started: boolean;
        snapshots: number;
      }>((resolve, reject) => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}?room=${room}`);
        let welcome = false;
        let lobby = false;
        let started = false;
        let snapshots = 0;
        const timer = setTimeout(() => {
          ws.close();
          reject(new Error(`timeout (${role}): welcome=${welcome} lobby=${lobby} start=${started} snaps=${snapshots}`));
        }, 8000);

        ws.on("open", () => {
          ws.send(
            JSON.stringify({ type: "join", roomId: room, name: role, role }),
          );
        });

        ws.on("message", (data) => {
          const msg = JSON.parse(String(data)) as {
            type: string;
            players?: { ready: boolean }[];
          };
          if (msg.type === "welcome") {
            welcome = true;
            ws.send(JSON.stringify({ type: "ready", ready: true }));
          }
          if (msg.type === "lobby") lobby = true;
          if (msg.type === "start") started = true;
          if (msg.type === "snapshot") snapshots++;
          if (welcome && started && snapshots >= 2) {
            clearTimeout(timer);
            ws.close();
            resolve({ welcome, lobby, started, snapshots });
          }
        });

        ws.on("error", reject);
      });

    const roomId = `e2e-${Date.now()}`;
    const [a, b] = await Promise.all([
      joinClient(roomId, "player"),
      joinClient(roomId, "opponent"),
    ]);

    expect(a.welcome).toBe(true);
    expect(a.lobby).toBe(true);
    expect(a.started).toBe(true);
    expect(a.snapshots).toBeGreaterThan(0);
    expect(b.started).toBe(true);
    expect(b.snapshots).toBeGreaterThan(0);
  });
});
