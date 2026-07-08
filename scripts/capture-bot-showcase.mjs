#!/usr/bin/env node
/**
 * Скриншоты ботов по типам (ниндзя, зомби, они…).
 * Usage: node scripts/capture-bot-showcase.mjs [--port=5199]
 */
import { existsSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createConnection } from "node:net";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const outDir = resolve(root, "test-artifacts/bot-showcase");

const portArg = process.argv.find((a) => a.startsWith("--port="));
const port = portArg ? Number(portArg.split("=")[1]) : 5199;
const base = `http://127.0.0.1:${port}`;

const SHOWCASE = [
  { kind: "ninja", ids: ["ninja", "ninja-2", "ninja-3"] },
  { kind: "zombie", ids: ["zombie", "zombie-2", "zombie-3"] },
  { kind: "oni", ids: ["oni", "oni-2", "oni-3"] },
  { kind: "robot", ids: ["robot", "robot-2", "robot-3"] },
];

function portOpen(p) {
  return new Promise((ok) => {
    const s = createConnection({ port: p, host: "127.0.0.1" });
    s.once("connect", () => { s.end(); ok(true); });
    s.on("error", () => ok(false));
  });
}

function resolveChrome(puppeteer) {
  for (const c of [
    process.env.PUPPETEER_EXECUTABLE_PATH,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
  ]) {
    if (typeof c === "string" && existsSync(c)) return c;
  }
  try {
    const p = puppeteer.executablePath?.() ?? puppeteer.default?.executablePath?.();
    if (typeof p === "string" && existsSync(p)) return p;
  } catch { /* ignore */ }
  return undefined;
}

async function captureBot(browser, faceId, kind, index) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 2 });
  await page.evaluateOnNewDocument(() => {
    const key = "ragdoll-faces-profile";
    let profile = {};
    try { profile = JSON.parse(localStorage.getItem(key) || "{}"); } catch { /* */ }
    localStorage.setItem(key, JSON.stringify({
      ...profile,
      name: "E2E",
      useCamera: false,
      avatarFaceId: "cat",
    }));
  });
  const url = `${base}/?e2e=quick&botFace=${encodeURIComponent(faceId)}`;
  await page.goto(url, { waitUntil: "load", timeout: 60_000 });
  await page.waitForSelector("canvas", { timeout: 45_000 });
  await new Promise((r) => setTimeout(r, 2800));
  const file = resolve(outDir, `${kind}-${index + 1}-${faceId}.png`);
  await page.screenshot({ path: file, type: "png" });
  await page.close();
  console.log(`  📸 ${kind}-${index + 1} (${faceId})`);
  return file;
}

async function main() {
  if (!(await portOpen(port))) {
    throw new Error(`vite not running on :${port} — yarn dev`);
  }
  mkdirSync(outDir, { recursive: true });
  const puppeteer = await import("puppeteer");
  const executablePath = resolveChrome(puppeteer);
  if (!executablePath) throw new Error("Chrome not found");

  const browser = await puppeteer.default.launch({
    headless: true,
    executablePath,
    args: ["--no-sandbox", "--disable-gpu"],
  });

  console.log(`\nBot showcase → ${outDir}\n`);
  try {
    for (const { kind, ids } of SHOWCASE) {
      for (let i = 0; i < ids.length; i += 1) {
        await captureBot(browser, ids[i], kind, i);
      }
    }
    console.log(`\nDone: ${outDir}\n`);
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
