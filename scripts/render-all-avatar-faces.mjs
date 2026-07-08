#!/usr/bin/env node
/**
 * Одна картинка со всеми лицами ростера.
 * Usage: node scripts/render-all-avatar-faces.mjs [--port=5199]
 */
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const outPath = resolve(root, "test-artifacts/all-avatar-faces.png");

const portArg = process.argv.find((a) => a.startsWith("--port="));
const port = portArg ? Number(portArg.split("=")[1]) : 5199;
const baseUrl = `http://127.0.0.1:${port}/`;

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

async function waitForHttp(url, ms = 30_000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {
      /* retry */
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error(`Server not ready: ${url}`);
}

const RENDER_JS = `
(async () => {
  const { AVATAR_FACE_PRESETS } = await import('/src/face/avatarPresets.ts');
  const { drawAvatarFacePreview } = await import('/src/face/drawAvatarFace.ts');
  const n = AVATAR_FACE_PRESETS.length;
  const cols = 20;
  const rows = Math.ceil(n / cols);
  const cell = 72;
  const labelH = 14;
  const pad = 8;
  const w = cols * cell + pad * 2;
  const h = rows * (cell + labelH) + pad * 2;
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#14141c';
  ctx.fillRect(0, 0, w, h);
  const tile = document.createElement('canvas');
  tile.width = cell;
  tile.height = cell;
  const tctx = tile.getContext('2d');
  ctx.font = '9px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  for (let i = 0; i < n; i += 1) {
    const p = AVATAR_FACE_PRESETS[i];
    const col = i % cols;
    const row = Math.floor(i / cols);
    const x = pad + col * cell;
    const y = pad + row * (cell + labelH);
    drawAvatarFacePreview(tctx, cell, p);
    ctx.drawImage(tile, x, y);
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.fillText(p.label.ru, x + cell / 2, y + cell + 2);
  }
  return { dataUrl: c.toDataURL('image/png'), count: n, w, h };
})()
`;

async function main() {
  await waitForHttp(baseUrl);
  const puppeteer = await import("puppeteer");
  const executablePath = resolveChromeExecutable(puppeteer);
  if (!executablePath) {
    throw new Error("Chrome not found. Set PUPPETEER_EXECUTABLE_PATH or install Chrome.");
  }
  const browser = await puppeteer.default.launch({
    headless: true,
    executablePath,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });
  try {
    const page = await browser.newPage();
    await page.goto(baseUrl, { waitUntil: "networkidle0", timeout: 60_000 });
    const result = await page.evaluate(RENDER_JS);
    const b64 = result.dataUrl.replace(/^data:image\/png;base64,/, "");
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, Buffer.from(b64, "base64"));
    console.log(`Saved ${result.count} faces → ${outPath} (${result.w}×${result.h})`);
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
