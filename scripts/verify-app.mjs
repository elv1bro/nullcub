#!/usr/bin/env node
/**
 * Реальная проверка игры в Chrome (Puppeteer): меню, бой с ботом, мастерская, WS-дуэль.
 *
 * Usage:
 *   yarn verify:browser
 *   node scripts/verify-app.mjs --port=5199 --keep-server
 *   node scripts/verify-app.mjs --skip-duel
 */
import { spawn, execSync } from "node:child_process";
import { createConnection } from "node:net";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

const portArg = process.argv.find((a) => a.startsWith("--port="));
const vitePort = portArg ? Number(portArg.split("=")[1]) : 5199;
const wsPort = 8796;
const debugPort = wsPort + 1;
const skipDuel = process.argv.includes("--skip-duel");
const keepServer = process.argv.includes("--keep-server");

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function portOpen(port) {
  return new Promise((resolvePort) => {
    const s = createConnection({ port, host: "127.0.0.1" });
    s.once("connect", () => {
      s.end();
      resolvePort(true);
    });
    s.on("error", () => resolvePort(false));
  });
}

async function waitForPort(port, label, ms = 45_000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    if (await portOpen(port)) return;
    await sleep(300);
  }
  throw new Error(`${label} not ready on :${port}`);
}

async function waitForHttp(url, ms = 45_000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {
      /* retry */
    }
    await sleep(300);
  }
  throw new Error(`HTTP not ready: ${url}`);
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

async function waitE2E(page, scenario, timeoutMs = 90_000) {
  await page.waitForFunction(
    (name) => {
      const h = window.__RAGDOLL_E2E__;
      return h?.scenario === name && (h.phase === "ok" || h.phase === "fail");
    },
    { timeout: timeoutMs },
    scenario,
  );
  const result = await page.evaluate(() => {
    const h = window.__RAGDOLL_E2E__;
    return { phase: h?.phase, error: h?.error, metrics: h?.metrics };
  });
  if (result.phase !== "ok") {
    throw new Error(result.error ?? `${scenario} failed`);
  }
  return result.metrics ?? {};
}

function resolveChromeExecutable(puppeteerMod) {
  const fromEnv = process.env.PUPPETEER_EXECUTABLE_PATH;
  if (typeof fromEnv === "string" && existsSync(fromEnv)) return fromEnv;

  try {
    const raw =
      puppeteerMod.executablePath?.() ??
      puppeteerMod.default?.executablePath?.();
    const fromPkg = raw && typeof raw.then === "function" ? undefined : raw;
    if (typeof fromPkg === "string" && existsSync(fromPkg)) return fromPkg;
  } catch {
    /* fall through */
  }

  for (const candidate of [
    "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ]) {
    if (existsSync(candidate)) return candidate;
  }

  return undefined;
}

async function prepareE2EPage(page) {
  await page.evaluateOnNewDocument(() => {
    const key = "ragdoll-faces-profile";
    let profile = {};
    try {
      profile = JSON.parse(localStorage.getItem(key) || "{}");
    } catch {
      /* ignore */
    }
    localStorage.setItem(
      key,
      JSON.stringify({
        ...profile,
        name: profile.name || "E2E",
        useCamera: false,
        useMicrophone: false,
      }),
    );
    // Skip first-visit overlays so harness can assert editor/battle chrome.
    localStorage.setItem("ragdoll-workshop-onboarded", "1");
    localStorage.setItem("ragdoll-battle-onboarded", "1");
  });
}

async function launchBrowser(puppeteerMod) {
  const executablePath = resolveChromeExecutable(puppeteerMod);
  if (!executablePath) {
    throw new Error(
      "Chrome not found. Install Google Chrome or: npx puppeteer browsers install chrome",
    );
  }

  // На Apple Silicon + x64 Node bundled Chromium через Rosetta часто
  // зависает на "Waiting for WS endpoint". Системный universal Chrome + pipe
  // обходит websocket-handshake timeout.
  const launchOpts = {
    headless: true,
    executablePath,
    pipe: true,
    timeout: 90_000,
    protocolTimeout: 120_000,
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--use-fake-ui-for-media-stream",
      "--use-fake-device-for-media-stream",
    ],
  };

  try {
    return await puppeteerMod.default.launch(launchOpts);
  } catch (firstErr) {
    // Fallback без pipe (старые окружения).
    console.warn(
      "  ! chrome launch with pipe failed, retry without pipe:",
      firstErr?.message ?? firstErr,
    );
    return await puppeteerMod.default.launch({
      ...launchOpts,
      pipe: false,
    });
  }
}

async function runScenario(browser, base, name, path) {
  const page = await browser.newPage();
  page.setDefaultTimeout(60_000);
  await prepareE2EPage(page);
  try {
    await page.goto(`${base}${path}`, { waitUntil: "load", timeout: 60_000 });
    const metrics = await waitE2E(page, name);
    console.log(`  ✓ ${name}`, metrics);
    return metrics;
  } finally {
    await page.close();
  }
}

async function waitForReadyButton(page, timeoutMs = 45_000) {
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("button")].some((b) =>
        /я готов|готов ✓/i.test(b.textContent ?? ""),
      ),
    { timeout: timeoutMs },
  );
}

async function clickReady(page) {
  const clicked = await page.evaluate(() => {
    const btn = [...document.querySelectorAll("button")].find((b) =>
      /я готов|готов ✓/i.test(b.textContent ?? ""),
    );
    if (!btn) return false;
    if (/готов ✓/i.test(btn.textContent ?? "")) return true;
    btn.click();
    return true;
  });
  if (!clicked) throw new Error("ready button not found");
}

async function runDuelScenario(browser, base) {
  killPort(wsPort);
  killPort(debugPort);
  await sleep(300);

  const server = spawn("yarn", ["server"], {
    cwd: root,
    shell: true,
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      PORT: String(wsPort),
      RAGDOLL_DEBUG: "1",
      DEBUG_HTTP_PORT: String(debugPort),
    },
  });

  try {
    await waitForPort(wsPort, "WS server");
    await waitForHttp(`http://127.0.0.1:${debugPort}/debug`, 20_000);
    const room = `verify-${Date.now()}`;
    const q = (devHub, joinName) =>
      `?devHub=${devHub}&room=${room}&wsPort=${wsPort}&server=ws://127.0.0.1:${wsPort}&joinName=${joinName}&e2e=duel`;

    const host = await browser.newPage();
    const guest = await browser.newPage();
    await prepareE2EPage(host);
    await prepareE2EPage(guest);
    host.setDefaultTimeout(60_000);
    guest.setDefaultTimeout(60_000);

    await Promise.all([
      host.goto(`${base}/${q("host", "Host")}`, {
        waitUntil: "load",
        timeout: 60_000,
      }),
      guest.goto(`${base}/${q("guest", "Guest")}`, {
        waitUntil: "load",
        timeout: 60_000,
      }),
    ]);

    await Promise.all([waitForReadyButton(host), waitForReadyButton(guest)]);

    await clickReady(host);
    await clickReady(guest);

    const metrics = await waitE2E(host, "duel", 60_000);
    console.log("  ✓ ws-duel", metrics);

    await host.close();
    await guest.close();
    return metrics;
  } finally {
    if (server && !server.killed) {
      server.kill("SIGTERM");
      await sleep(400);
      if (!server.killed) server.kill("SIGKILL");
    }
    killPort(wsPort);
    killPort(debugPort);
  }
}

async function main() {
  let vite = null;
  const viteAlreadyUp = await portOpen(vitePort);

  if (!viteAlreadyUp) {
    vite = spawn("yarn", ["dev", "--host", "127.0.0.1", "--port", String(vitePort)], {
      cwd: root,
      shell: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, FORCE_COLOR: "0" },
    });
    await waitForHttp(`http://127.0.0.1:${vitePort}/`);
  } else {
    console.log(`vite already on :${vitePort}`);
  }

  let puppeteer;
  try {
    puppeteer = await import("puppeteer");
  } catch {
    console.error("Install puppeteer: yarn add -D puppeteer");
    process.exit(1);
  }

  const browser = await launchBrowser(puppeteer);

  const base = `http://127.0.0.1:${vitePort}`;
  const results = [];

  try {
    console.log("\n=== Browser verify ===\n");

    results.push(await runScenario(browser, base, "menu", "/?e2e=menu"));
    results.push(
      await runScenario(browser, base, "authGate", "/?e2e=authGate"),
    );
    results.push(await runScenario(browser, base, "lobby", "/?e2e=lobby"));
    results.push(
      await runScenario(browser, base, "roguelike", "/?e2e=roguelike"),
    );
    results.push(await runScenario(browser, base, "quick", "/?e2e=quick"));
    results.push(await runScenario(browser, base, "workshop", "/?e2e=workshop"));
    results.push(
      await runScenario(browser, base, "workshopFight", "/?e2e=workshopFight"),
    );

    if (!skipDuel) {
      results.push(await runDuelScenario(browser, base));
    } else {
      console.log("  ⊘ ws-duel skipped");
    }

    console.log(
      "\n=== OK: menu + authGate + lobby + roguelike + quick + workshop + workshopFight" +
        (skipDuel ? "" : " + ws-duel") +
        " ===\n",
    );
  } finally {
    await browser.close();
    if (vite && !keepServer) {
      vite.kill("SIGTERM");
    }
  }
}

main().catch((err) => {
  console.error("\nVERIFY FAILED:", err.message ?? err);
  process.exit(1);
});
