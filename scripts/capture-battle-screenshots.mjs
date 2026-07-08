#!/usr/bin/env node
/**
 * Скриншоты боя для визуальной проверки verify-тестов.
 * Usage: yarn verify:screenshots
 */
import { spawn, execSync } from "node:child_process";
import { createConnection } from "node:net";
import { existsSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const outDir = resolve(root, "test-artifacts/battle-screenshots");

const portArg = process.argv.find((a) => a.startsWith("--port="));
const vitePort = portArg ? Number(portArg.split("=")[1]) : 5199;
const wsPort = 8796;
const debugPort = wsPort + 1;

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
    /* ignore */
  }
  for (const candidate of [
    "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ]) {
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

async function prepareE2EPage(page) {
  await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 1 });
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
  });
}

async function waitForBattleCanvas(page, timeoutMs = 45_000) {
  await page.waitForSelector("canvas", { timeout: timeoutMs });
  await page.waitForFunction(
    () => {
      const canvas = document.querySelector("canvas");
      return canvas instanceof HTMLCanvasElement && canvas.width > 0;
    },
    { timeout: timeoutMs },
  );
}

async function waitForBattleHud(page, timeoutMs = 45_000) {
  await waitForBattleCanvas(page, timeoutMs);
  await page.waitForFunction(
    () => /wasd/i.test(document.body.innerText ?? ""),
    { timeout: timeoutMs },
  );
  await sleep(2000);
}

async function readBattleMetrics(page) {
  return page.evaluate(() => {
    const h = window.__RAGDOLL_E2E__;
    const hearts = [...document.querySelectorAll("[class*='heart'], .hp-overlay, .HpOverlay")]
      .length;
    return {
      e2ePhase: h?.phase ?? null,
      e2eMetrics: h?.metrics ?? null,
      canvasCount: document.querySelectorAll("canvas").length,
      hasAbilityBar: Boolean(document.querySelector("button")?.textContent?.match(/dash|рывок|flip|reset|сброс/i)),
    };
  });
}

async function shot(page, name, note) {
  const path = resolve(outDir, `${name}.png`);
  await page.screenshot({ path, type: "png" });
  const metrics = await readBattleMetrics(page);
  console.log(`  📸 ${name}.png — ${note}`, metrics);
  return path;
}

async function captureQuickBattle(browser, base) {
  const page = await browser.newPage();
  page.setDefaultTimeout(60_000);
  await prepareE2EPage(page);
  await page.goto(`${base}/?e2e=quick`, { waitUntil: "load", timeout: 60_000 });
  await waitForBattleCanvas(page);
  await sleep(1500);
  await shot(page, "01-quick-battle-start", "бой с ботом, ~1.5с после canvas");
  await sleep(3500);
  await shot(page, "02-quick-battle-mid", "бой с ботом, ~5с — боты дерутся");
  await page.close();
}

async function waitForReadyButton(page) {
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("button")].some((b) =>
        /я готов|готов ✓/i.test(b.textContent ?? ""),
      ),
    { timeout: 45_000 },
  );
}

async function clickReady(page) {
  await page.evaluate(() => {
    const btn = [...document.querySelectorAll("button")].find((b) =>
      /я готов|готов ✓/i.test(b.textContent ?? ""),
    );
    if (!btn) throw new Error("ready button not found");
    if (!/готов ✓/i.test(btn.textContent ?? "")) btn.click();
  });
}

async function captureWsDuel(browser, base) {
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
    for (let i = 0; i < 40 && !(await portOpen(wsPort)); i++) {
      await sleep(250);
    }
    if (!(await portOpen(wsPort))) throw new Error("WS server failed to start");
    await waitForHttp(`http://127.0.0.1:${debugPort}/debug`, 20_000);

    const room = `shots-${Date.now()}`;
    const q = (devHub, joinName) =>
      `?devHub=${devHub}&room=${room}&wsPort=${wsPort}&server=ws://127.0.0.1:${wsPort}&joinName=${joinName}&e2e=duel`;

    const host = await browser.newPage();
    const guest = await browser.newPage();
    await prepareE2EPage(host);
    await prepareE2EPage(guest);

    await Promise.all([
      host.goto(`${base}/${q("host", "Host")}`, { waitUntil: "load" }),
      guest.goto(`${base}/${q("guest", "Guest")}`, { waitUntil: "load" }),
    ]);

    await host.waitForFunction(
      () =>
        (document.body.innerText ?? "").includes("Комната ожидания") ||
        (document.body.innerText ?? "").includes("Я готов"),
      { timeout: 45_000 },
    );
    await shot(host, "03-ws-duel-lobby-host", "лобби host до ready");
    await Promise.all([waitForReadyButton(host), waitForReadyButton(guest)]);
    await clickReady(host);
    await clickReady(guest);

    await waitForBattleHud(host, 60_000);
    await shot(host, "04-ws-duel-battle-host", "WS-дуэль host — HUD + canvas");
    await sleep(5000);
    await shot(host, "05-ws-duel-battle-host-late", "WS-дуэль host ~5с в бою");

    await host.close();
    await guest.close();
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

async function captureWorkshop(browser, base) {
  const page = await browser.newPage();
  await prepareE2EPage(page);
  await page.goto(`${base}/?e2e=workshop`, { waitUntil: "load" });
  await page.waitForSelector(".workshop-root", { timeout: 30_000 });
  await sleep(1200);
  await shot(page, "06-workshop", "мастерская с монстром");
  await page.close();
}

async function main() {
  mkdirSync(outDir, { recursive: true });

  if (!(await portOpen(vitePort))) {
    throw new Error(`vite not running — start: yarn dev (port ${vitePort})`);
  }

  const puppeteer = await import("puppeteer");
  const executablePath = resolveChromeExecutable(puppeteer);
  if (!executablePath) {
    throw new Error("Chrome not found. Run: npx puppeteer browsers install chrome");
  }

  const browser = await puppeteer.default.launch({
    headless: true,
    executablePath,
    args: ["--no-sandbox", "--disable-gpu", "--use-fake-ui-for-media-stream"],
  });

  const base = `http://127.0.0.1:${vitePort}`;
  console.log(`\nCapturing screenshots → ${outDir}\n`);

  try {
    await captureQuickBattle(browser, base);
    try {
      await captureWsDuel(browser, base);
    } catch (err) {
      console.warn("  ⚠ ws-duel screenshots skipped:", err.message ?? err);
    }
    await captureWorkshop(browser, base);
    console.log(`\nDone. Open: ${outDir}\n`);
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error("CAPTURE FAILED:", err.message ?? err);
  process.exit(1);
});
