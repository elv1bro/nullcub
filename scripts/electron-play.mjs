#!/usr/bin/env node
/**
 * Обычный запуск игры в Electron (меню), без Dev Hub / guest-комнат.
 * Usage: env -u ELECTRON_RUN_AS_NODE yarn electron:play
 */
import { app, BrowserWindow } from "electron";
import { spawn } from "node:child_process";
import { createConnection } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const VITE_PORT = Number(process.env.VITE_PORT ?? 5199);
const GAME_URL = `http://127.0.0.1:${VITE_PORT}/`;

/** @type {import("child_process").ChildProcess | null} */
let viteProcess = null;

function portOpen(port) {
  return new Promise((resolve) => {
    const socket = createConnection({ port, host: "127.0.0.1" });
    socket.once("connect", () => {
      socket.end();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

async function waitForPort(port, timeoutMs = 60_000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await portOpen(port)) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`Timed out waiting for :${port}`);
}

async function ensureVite() {
  if (await portOpen(VITE_PORT)) return;
  viteProcess = spawn("yarn", ["dev"], {
    cwd: ROOT,
    shell: true,
    stdio: "inherit",
    env: { ...process.env, FORCE_COLOR: "1" },
  });
  await waitForPort(VITE_PORT);
}

app.whenReady().then(async () => {
  try {
    await ensureVite();
    const win = new BrowserWindow({
      width: 1280,
      height: 800,
      title: "Ragdoll Riot",
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
      },
    });
    win.loadURL(GAME_URL);
    console.log(`[electron:play] ${GAME_URL}`);
  } catch (err) {
    console.error("[electron:play] boot failed:", err);
    app.quit();
  }
});

app.on("window-all-closed", () => {
  if (viteProcess && !viteProcess.killed) viteProcess.kill("SIGTERM");
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => {
  if (viteProcess && !viteProcess.killed) viteProcess.kill("SIGTERM");
});
