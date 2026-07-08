import { app, BrowserWindow, clipboard, ipcMain } from "electron";
import { spawn, execSync } from "node:child_process";
import { createConnection } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const VITE_PORT = Number(process.env["VITE_PORT"] ?? 5199);
const WS_PORT = Number(process.env["WS_PORT"] ?? 8787);
const DEBUG_HTTP_PORT = Number(process.env["DEBUG_HTTP_PORT"] ?? WS_PORT + 1);
const ROOM = process.env["RAGDOLL_ROOM"] ?? "dev";
const REQUIRED_SERVER_BUILD = "duel-settle-v4";

const modeArg = process.argv.find((a) => a.startsWith("--mode="));
const MODE = modeArg?.split("=")[1] === "client" ? "client" : "hub";

/** @type {import("child_process").ChildProcess | null} */
let viteProcess = null;
/** @type {import("child_process").ChildProcess | null} */
let serverProcess = null;
/** @type {boolean} */
let spawnedServer = false;
/** @type {BrowserWindow | null} */
let mainWindow = null;
/** @type {BrowserWindow | null} */
let guestWindow = null;

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
  throw new Error(`Timed out waiting for port ${port}`);
}

async function ensureVite() {
  if (await portOpen(VITE_PORT)) return;
  viteProcess = spawn("yarn", ["dev"], {
    cwd: ROOT,
    shell: true,
    stdio: "inherit",
    env: { ...process.env, FORCE_COLOR: "1" },
  });
  viteProcess.on("exit", (code) => {
    if (code && code !== 0) console.error(`[electron] vite exited ${code}`);
  });
  await waitForPort(VITE_PORT);
}

async function verifyDebugServer() {
  try {
    const res = await fetch(`http://127.0.0.1:${DEBUG_HTTP_PORT}/debug`);
    if (!res.ok) return false;
    const data = await res.json();
    return data.serverBuildId === REQUIRED_SERVER_BUILD;
  } catch {
    return false;
  }
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

async function ensureWsServer() {
  if (await portOpen(WS_PORT)) {
    if (await verifyDebugServer()) {
      console.log(`[electron] WS ok (${REQUIRED_SERVER_BUILD}) on :${WS_PORT}`);
      return;
    }
    console.warn(
      `[electron] stale WS on :${WS_PORT} — killing old process and starting fresh server`,
    );
    killPort(WS_PORT);
    killPort(DEBUG_HTTP_PORT);
    await new Promise((r) => setTimeout(r, 400));
  }

  serverProcess = spawn("yarn", ["server"], {
    cwd: ROOT,
    shell: true,
    stdio: "inherit",
    env: {
      ...process.env,
      PORT: String(WS_PORT),
      RAGDOLL_DEBUG: "1",
      DEBUG_HTTP_PORT: String(DEBUG_HTTP_PORT),
    },
  });
  spawnedServer = true;
  serverProcess.on("exit", (code) => {
    if (code && code !== 0) console.error(`[electron] server exited ${code}`);
    serverProcess = null;
    spawnedServer = false;
  });
  await waitForPort(WS_PORT);
  if (!(await verifyDebugServer())) {
    throw new Error(
      `WS server on :${WS_PORT} missing build ${REQUIRED_SERVER_BUILD}. Run: lsof -ti:${WS_PORT} | xargs kill -9 && yarn server`,
    );
  }
  console.log(`[electron] WS server ws://127.0.0.1:${WS_PORT} (${REQUIRED_SERVER_BUILD})`);
}

function joinUrl(role, name) {
  const q = new URLSearchParams({
    devHub: role === "player" ? "host" : "guest",
    room: ROOM,
    wsPort: String(WS_PORT),
    server: `ws://127.0.0.1:${WS_PORT}`,
    joinName: name,
  });
  return `http://127.0.0.1:${VITE_PORT}/?${q}`;
}

function devtoolsUrl() {
  const q = new URLSearchParams({
    room: ROOM,
    wsPort: String(WS_PORT),
    vitePort: String(VITE_PORT),
  });
  return `http://127.0.0.1:${VITE_PORT}/devtools.html?${q}`;
}

function devConfig() {
  return {
    mode: MODE,
    room: ROOM,
    wsPort: WS_PORT,
    vitePort: VITE_PORT,
    hostJoinUrl: joinUrl("player", "Host"),
    guestJoinUrl: joinUrl("opponent", "Guest"),
  };
}

async function getServerStats() {
  const empty = { wsPort: WS_PORT, roomCount: 0, rooms: [], wsRunning: false };
  try {
    const res = await fetch(`http://127.0.0.1:${DEBUG_HTTP_PORT}/debug`);
    if (!res.ok) return empty;
    return { ...(await res.json()), wsRunning: true };
  } catch {
    return empty;
  }
}

function createWindow(url, title) {
  const win = new BrowserWindow({
    width: MODE === "hub" ? 1280 : 960,
    height: MODE === "hub" ? 800 : 720,
    title,
    webPreferences: {
      preload: join(ROOT, "electron/preload.mjs"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadURL(url);
  win.webContents.setWindowOpenHandler(({ url: target }) => {
    if (target.startsWith("http://127.0.0.1")) {
      const child = new BrowserWindow({
        width: 960,
        height: 720,
        webPreferences: {
          preload: join(ROOT, "electron/preload.mjs"),
          contextIsolation: true,
          nodeIntegration: false,
        },
      });
      child.loadURL(target);
    }
    return { action: "deny" };
  });
  return win;
}

function registerIpc() {
  ipcMain.handle("dev:config", () => devConfig());
  ipcMain.handle("dev:stats", () => getServerStats());
  ipcMain.handle("dev:copy-guest-url", () => {
    const url = joinUrl("opponent", "Guest");
    clipboard.writeText(url);
    return url;
  });
  ipcMain.handle("dev:open-guest-window", () => {
    if (guestWindow && !guestWindow.isDestroyed()) {
      guestWindow.focus();
      return joinUrl("opponent", "Guest");
    }
    guestWindow = createWindow(joinUrl("opponent", "Guest"), "Ragdoll — Guest");
    guestWindow.on("closed", () => {
      guestWindow = null;
    });
    return joinUrl("opponent", "Guest");
  });
}

async function bootHub() {
  await ensureVite();
  await ensureWsServer();
  mainWindow = createWindow(devtoolsUrl(), "Ragdoll Dev Hub");
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

async function bootClient() {
  await ensureVite();
  mainWindow = createWindow(joinUrl("opponent", "Guest"), "Ragdoll — Guest Client");
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  registerIpc();
  try {
    if (MODE === "hub") await bootHub();
    else await bootClient();
  } catch (err) {
    console.error("[electron] boot failed:", err);
    app.quit();
  }
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => {
  if (spawnedServer && serverProcess && !serverProcess.killed) {
    serverProcess.kill("SIGTERM");
    serverProcess = null;
  }
  if (viteProcess && !viteProcess.killed) {
    viteProcess.kill("SIGTERM");
    viteProcess = null;
  }
});
