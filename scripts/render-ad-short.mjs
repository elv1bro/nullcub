#!/usr/bin/env node
/**
 * Рекламный probe: /?ad=probe → JPEG-кадры → mp4 + музыка меню.
 *
 * menu-theme.ogg = Theora+Vorbis (не чистый audio) — сначала выдираем звук.
 *
 * Usage:
 *   yarn dev
 *   yarn ad:probe
 */
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createConnection } from "node:net";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const outDir = resolve(root, "test-artifacts/ad-shorts");
const menuThemeSrc = resolve(root, "public/sounds/music/menu-theme.ogg");

const portArg = process.argv.find((a) => a.startsWith("--port="));
const port = portArg ? Number(portArg.split("=")[1]) : 5199;
const base = `http://127.0.0.1:${port}`;

function portOpen(p) {
  return new Promise((ok) => {
    const s = createConnection({ port: p, host: "127.0.0.1" });
    s.once("connect", () => {
      s.end();
      ok(true);
    });
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
    const p =
      puppeteer.executablePath?.() ?? puppeteer.default?.executablePath?.();
    if (typeof p === "string" && existsSync(p)) return p;
  } catch {
    /* ignore */
  }
  return undefined;
}

/** menu-theme.ogg содержит Theora video — для mux нужен чистый audio. */
function extractMenuAudio(outAac) {
  if (!existsSync(menuThemeSrc)) {
    throw new Error(`menu theme missing: ${menuThemeSrc}`);
  }
  execFileSync(
    "ffmpeg",
    ["-y", "-i", menuThemeSrc, "-vn", "-c:a", "aac", "-b:a", "192k", outAac],
    { stdio: "ignore" },
  );
  if (!existsSync(outAac)) throw new Error("failed to extract menu audio");
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

  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const framesDir = resolve(outDir, `frames-${stamp}`);
  const mp4Path = resolve(outDir, `probe-${stamp}.mp4`);
  const audioAac = resolve(outDir, `menu-theme-${stamp}.m4a`);
  mkdirSync(framesDir, { recursive: true });

  console.log(`\nAd probe → ${outDir}\n`);

  try {
    console.log("  extract menu audio (strip Theora)…");
    extractMenuAudio(audioAac);

    const page = await browser.newPage();
    await page.setViewport({ width: 1080, height: 1920, deviceScaleFactor: 1 });
    await page.goto(`${base}/?ad=probe&record=wait`, {
      waitUntil: "networkidle0",
      timeout: 60_000,
    });
    await page.waitForFunction(() => window.__RAGDOLL_AD__?.ready === true, {
      timeout: 30_000,
    });
    await page.evaluate(async () => {
      if (document.fonts?.ready) await document.fonts.ready;
    });

    console.log("  offline record @ 30fps…");
    page.setDefaultTimeout(180_000);
    const result = await page.evaluate(async () => {
      const api = window.__RAGDOLL_AD__;
      if (!api) throw new Error("no __RAGDOLL_AD__");
      return api.record();
    });

    const fps = result?.fps || 30;
    const frames = result?.frames || [];
    if (frames.length < 20) {
      throw new Error(`too few frames: ${frames.length}`);
    }

    for (let i = 0; i < frames.length; i += 1) {
      const file = join(framesDir, `f-${String(i).padStart(4, "0")}.jpg`);
      writeFileSync(file, Buffer.from(frames[i], "base64"));
    }
    console.log(`  ✓ ${frames.length} frames → ${framesDir}`);

    const durationSec = frames.length / fps;
    const fadeOutStart = Math.max(0, durationSec - 1.4);

    console.log("  mux video + menu music…");
    execFileSync(
      "ffmpeg",
      [
        "-y",
        "-framerate",
        String(fps),
        "-i",
        join(framesDir, "f-%04d.jpg"),
        "-i",
        audioAac,
        "-filter_complex",
        `[1:a]afade=t=in:st=0:d=0.5,afade=t=out:st=${fadeOutStart.toFixed(2)}:d=1.3,atrim=0:${durationSec.toFixed(3)},asetpts=PTS-STARTPTS[a]`,
        "-map",
        "0:v:0",
        "-map",
        "[a]",
        "-c:v",
        "libx264",
        "-preset",
        "slow",
        "-crf",
        "16",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-shortest",
        "-movflags",
        "+faststart",
        mp4Path,
      ],
      { stdio: "inherit" },
    );

    // sanity: must have audio stream
    const probe = execFileSync(
      "ffprobe",
      [
        "-v",
        "error",
        "-select_streams",
        "a",
        "-show_entries",
        "stream=codec_type",
        "-of",
        "csv=p=0",
        mp4Path,
      ],
      { encoding: "utf8" },
    ).trim();
    if (!probe.includes("audio")) {
      throw new Error(`mp4 has no audio stream: ${mp4Path}`);
    }

    console.log(`  ✓ ${mp4Path}`);
    console.log(`     frames=${frames.length} fps=${fps} dur=${durationSec.toFixed(1)}s + audio`);
    console.log("\nDone.\n");
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
