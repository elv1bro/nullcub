#!/usr/bin/env node
/**
 * Smoke: поднимает WS, двое join+ready, 12s idle — гость не должен умереть.
 * Usage: node --import tsx/esm scripts/duel-smoke.mjs
 */
import { spawn, execSync } from "node:child_process";
import { createConnection } from "node:net";
import { WebSocket } from "ws";
import {
  SERVER_BUILD_ID,
  SERVER_SPAWN_GRACE_MS,
  SERVER_SETTLE_TICKS,
} from "../src/server/serverConstants.ts";

const WS_PORT = 8795;
const DEBUG_PORT = WS_PORT + 1;
const ROOM = `smoke-${Date.now()}`;
const RUN_MS = 12_000;

function portOpen(port) {
  return new Promise((resolve) => {
    const s = createConnection({ port, host: "127.0.0.1" });
    s.once("connect", () => {
      s.end();
      resolve(true);
    });
    s.on("error", () => resolve(false));
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function killPort(port) {
  try {
    execSync(`lsof -ti:${port} | xargs kill -9 2>/dev/null || true`, {
      shell: true,
      stdio: "ignore",
    });
  } catch {
    /* ignore */
  }
}

async function main() {
  killPort(WS_PORT);
  killPort(DEBUG_PORT);
  await sleep(300);

  const server = spawn("yarn", ["server"], {
    cwd: new URL("..", import.meta.url).pathname,
    shell: true,
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      PORT: String(WS_PORT),
      RAGDOLL_DEBUG: "1",
      DEBUG_HTTP_PORT: String(DEBUG_PORT),
    },
  });

  let serverLog = "";
  server.stdout?.on("data", (d) => {
    serverLog += d;
  });
  server.stderr?.on("data", (d) => {
    serverLog += d;
  });

  for (let i = 0; i < 40 && !(await portOpen(WS_PORT)); i++) {
    await sleep(250);
  }
  if (!(await portOpen(WS_PORT))) {
    server.kill();
    console.error("server failed to start\n", serverLog);
    process.exit(1);
  }

  const debugRes = await fetch(`http://127.0.0.1:${DEBUG_PORT}/debug`);
  const debug = await debugRes.json();
  console.log("debug", {
    build: debug.serverBuildId,
    settle: debug.settleTicks,
    grace: debug.spawnGraceMs,
  });

  if (debug.serverBuildId !== SERVER_BUILD_ID) {
    server.kill();
    throw new Error(`wrong build: ${debug.serverBuildId}`);
  }

  const states = [];

  const connect = (role) =>
    new Promise((resolve, reject) => {
      const ws = new WebSocket(`ws://127.0.0.1:${WS_PORT}?room=${ROOM}`);
      ws.on("open", () => {
        ws.send(JSON.stringify({ type: "join", roomId: ROOM, name: role, role }));
      });
      ws.on("message", (raw) => {
        const msg = JSON.parse(String(raw));
        if (msg.type === "welcome") {
          ws.send(JSON.stringify({ type: "ready", ready: true }));
          resolve(ws);
        }
        if (msg.type === "battleState") {
          states.push({ t: Date.now(), role, ...msg.payload });
        }
      });
      ws.on("error", reject);
    });

  await Promise.all([connect("player"), connect("opponent")]);

  // settle (~3s async) + start
  await sleep(5000);

  const started = Date.now();
  await sleep(RUN_MS);

  server.kill();

  const guestStates = states.filter((s) => s.opponentHp != null);
  const death = guestStates.find((s) => s.opponentHp <= 0);
  const last = guestStates.at(-1);

  console.log("samples", guestStates.filter((_, i) => i % 5 === 0).map((s) => ({
    dt: ((s.t - started) / 1000).toFixed(1),
    player: Math.round(s.playerHp),
    guest: Math.round(s.opponentHp),
    over: s.battleOver,
  })));
  console.log("death", death ? { guest: death.opponentHp, dt: (death.t - started) / 1000 } : null);
  console.log("last", last ? { player: last.playerHp, guest: last.opponentHp } : null);

  if (death) {
    console.error("FAIL: guest died");
    process.exit(1);
  }
  if (!last || last.opponentHp <= 0) {
    console.error("FAIL: no battleState or guest hp 0");
    process.exit(1);
  }
  console.log(`OK: guest alive ${RUN_MS / 1000}s (settle=${SERVER_SETTLE_TICKS}, grace=${SERVER_SPAWN_GRACE_MS}ms)`);
  // WS-сокеты держат event loop — выходим явно
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
