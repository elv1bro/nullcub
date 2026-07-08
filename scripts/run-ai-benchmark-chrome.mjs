#!/usr/bin/env node
/**
 * Headless Chrome: прогон AI-бенчмарка в реальном браузере (Matter + WASM mediapipe не нужны).
 * Usage: node scripts/run-ai-benchmark-chrome.mjs [--rounds=3] [--port=5199]
 */
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

const roundsArg = process.argv.find((a) => a.startsWith("--rounds="));
const rounds = roundsArg ? Number(roundsArg.split("=")[1]) : 3;
const portArg = process.argv.find((a) => a.startsWith("--port="));
const port = portArg ? Number(portArg.split("=")[1]) : 5199;

async function waitForServer(url, ms = 30_000) {
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

async function main() {
  const vite = spawn("yarn", ["dev", "--host", "127.0.0.1", "--port", String(port)], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, FORCE_COLOR: "0" },
  });

  let viteLog = "";
  vite.stdout?.on("data", (d) => {
    viteLog += d.toString();
  });
  vite.stderr?.on("data", (d) => {
    viteLog += d.toString();
  });

  try {
    await waitForServer(`http://127.0.0.1:${port}/`);
  } catch (e) {
    vite.kill("SIGTERM");
    console.error(viteLog);
    throw e;
  }

  let puppeteer;
  try {
    puppeteer = await import("puppeteer");
  } catch {
    console.error(
      "puppeteer not installed. Run: yarn add -D puppeteer\nFalling back to vitest headless sim…",
    );
    vite.kill("SIGTERM");
    const { execSync } = await import("node:child_process");
    execSync("yarn vitest run src/battle/aiBenchmark.test.ts", {
      cwd: root,
      stdio: "inherit",
    });
    return;
  }

  const browser = await puppeteer.default.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-gpu"],
  });

  try {
    const page = await browser.newPage();
    const url = `http://127.0.0.1:${port}/benchmark.html?rounds=${rounds}`;
    await page.goto(url, { waitUntil: "networkidle0", timeout: 120_000 });
    await page.waitForFunction(() => window.__AI_BENCHMARK__ != null, {
      timeout: 300_000,
    });

    const report = await page.evaluate(() => window.__AI_BENCHMARK__);
    const md = await page.evaluate(() => document.getElementById("out")?.textContent ?? "");

    console.log(md);
    console.log("\n(JSON saved to benchmark-last.json)");
    await readFile(resolve(root, "benchmark-last.json")).catch(() => null);
    const { writeFile } = await import("node:fs/promises");
    await writeFile(
      resolve(root, "benchmark-last.json"),
      JSON.stringify(report, null, 2),
    );
  } finally {
    await browser.close();
    vite.kill("SIGTERM");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
