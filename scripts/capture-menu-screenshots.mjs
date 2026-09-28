#!/usr/bin/env node
/**
 * Обход всех экранов меню на десктопе и на телефоне.
 * Профиль не подкладывается — проверяем поведение чистой установки,
 * включая то, что игра не просит камеру на старте.
 *
 * Usage: yarn shots:menu   (нужен запущенный vite: yarn dev)
 */
import { createConnection } from "node:net";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const outDir = resolve(root, "test-artifacts/menu-screenshots");

const portArg = process.argv.find((a) => a.startsWith("--port="));
const vitePort = portArg ? Number(portArg.split("=")[1]) : 5199;

const VIEWPORTS = [
  { id: "desktop", width: 1280, height: 800 },
  { id: "phone-portrait", width: 390, height: 844, mobile: true },
  { id: "phone-landscape", width: 844, height: 390, mobile: true },
];

/** Экран меню = как на него попасть из главного меню. */
const SCREENS = [
  { id: "home", path: [] },
  { id: "play-pick", path: ["В бой"] },
  { id: "campaign", path: ["В бой", "Кампания"] },
  { id: "customize", path: ["Облик"] },
  { id: "achievements", path: ["Достижения"] },
  { id: "workshop-entry", path: [], skip: true },
  { id: "options", path: ["Настройки"] },
  { id: "controls", path: ["Управление"] },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function portOpen(port) {
  return new Promise((done) => {
    const s = createConnection({ port, host: "127.0.0.1" });
    s.once("connect", () => {
      s.end();
      done(true);
    });
    s.on("error", () => done(false));
  });
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

/** Ставит счётчик обращений к камере до загрузки приложения. */
async function trackCameraRequests(page) {
  await page.evaluateOnNewDocument(() => {
    window.__CAMERA_REQUESTS__ = 0;
    const media = navigator.mediaDevices;
    if (!media) return;
    const original = media.getUserMedia?.bind(media);
    media.getUserMedia = (...args) => {
      window.__CAMERA_REQUESTS__ += 1;
      return original
        ? original(...args)
        : Promise.reject(new Error("no camera"));
    };
  });
}

async function clickByText(page, text) {
  const clicked = await page.evaluate((label) => {
    const btn = [...document.querySelectorAll("button")].find(
      (b) => (b.textContent ?? "").trim() === label && !b.disabled,
    );
    if (!btn) return false;
    btn.click();
    return true;
  }, text);
  if (!clicked) throw new Error(`кнопка не найдена или отключена: "${text}"`);
  await sleep(450);
}

async function readScreenFacts(page) {
  return page.evaluate(() => {
    const buttons = [...document.querySelectorAll("button")];
    const visible = buttons.filter((b) => b.offsetParent !== null);
    const panel = document.querySelector(".menu-arena-ui__panel");
    return {
      cameraRequests: window.__CAMERA_REQUESTS__ ?? 0,
      buttons: visible.map((b) => (b.textContent ?? "").trim()).filter(Boolean),
      // data-locked — намеренная блокировка прогрессом, а не мёртвая кнопка.
      disabledButtons: visible
        .filter((b) => b.disabled && b.dataset.locked !== "true")
        .map((b) => (b.textContent ?? "").trim()),
      // Кнопка меньше 44px по высоте — промах пальцем.
      smallTapTargets: visible
        .filter((b) => b.getBoundingClientRect().height < 44)
        .map((b) => (b.textContent ?? "").trim())
        .filter(Boolean),
      panelOverflows: panel
        ? panel.scrollHeight > panel.clientHeight + 1
        : false,
      pageScrolls:
        document.documentElement.scrollHeight >
        document.documentElement.clientHeight + 1,
    };
  });
}

async function captureViewport(browser, base, viewport) {
  const page = await browser.newPage();
  page.setDefaultTimeout(30_000);
  await trackCameraRequests(page);
  await page.setViewport({
    width: viewport.width,
    height: viewport.height,
    deviceScaleFactor: 1,
    isMobile: Boolean(viewport.mobile),
    hasTouch: Boolean(viewport.mobile),
  });

  const problems = [];

  for (const screen of SCREENS) {
    if (screen.skip) continue;
    await page.goto(`${base}/?e2e=menu`, { waitUntil: "load" });
    await page.waitForSelector(".menu-arena-ui__panel");
    await sleep(600);

    try {
      for (const step of screen.path) await clickByText(page, step);
    } catch (err) {
      problems.push(`[${viewport.id}/${screen.id}] ${err.message}`);
      continue;
    }

    const name = `${viewport.id}--${screen.id}`;
    await page.screenshot({ path: resolve(outDir, `${name}.png`), type: "png" });

    const facts = await readScreenFacts(page);
    if (facts.cameraRequests > 0) {
      problems.push(`[${viewport.id}/${screen.id}] просит камеру на старте`);
    }
    if (facts.disabledButtons.length > 0) {
      problems.push(
        `[${viewport.id}/${screen.id}] мёртвые кнопки: ${facts.disabledButtons.join(", ")}`,
      );
    }
    if (viewport.mobile && facts.smallTapTargets.length > 0) {
      problems.push(
        `[${viewport.id}/${screen.id}] мелкие кнопки: ${facts.smallTapTargets.join(", ")}`,
      );
    }
    if (facts.pageScrolls) {
      problems.push(`[${viewport.id}/${screen.id}] страница прокручивается целиком`);
    }

    console.log(
      `  ${name}.png — кнопок ${facts.buttons.length}` +
        (facts.panelOverflows ? ", панель со скроллом" : ""),
    );
  }

  // Возврат в главное меню из самого глубокого экрана.
  await page.goto(`${base}/?e2e=menu`, { waitUntil: "load" });
  await page.waitForSelector(".menu-arena-ui__panel");
  await sleep(500);
  try {
    await clickByText(page, "В бой");
    await clickByText(page, "Кампания");
    await clickByText(page, "Главная");
    const backHome = await page.evaluate(() =>
      [...document.querySelectorAll("button")].some(
        (b) => (b.textContent ?? "").trim() === "В бой",
      ),
    );
    if (!backHome) {
      problems.push(`[${viewport.id}] «Главная» не возвращает в главное меню`);
    }
  } catch (err) {
    problems.push(`[${viewport.id}] путь назад сломан: ${err.message}`);
  }

  await page.close();
  return problems;
}

async function main() {
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });

  if (!(await portOpen(vitePort))) {
    throw new Error(`vite не запущен — стартуй: yarn dev (порт ${vitePort})`);
  }

  const puppeteer = await import("puppeteer");
  const executablePath = resolveChromeExecutable(puppeteer);
  if (!executablePath) {
    throw new Error("Chrome не найден. Запусти: npx puppeteer browsers install chrome");
  }

  const browser = await puppeteer.default.launch({
    headless: true,
    executablePath,
    args: ["--no-sandbox", "--disable-gpu"],
  });

  const base = `http://127.0.0.1:${vitePort}`;
  console.log(`\nСкриншоты меню → ${outDir}\n`);

  const problems = [];
  try {
    for (const viewport of VIEWPORTS) {
      console.log(`${viewport.id} (${viewport.width}x${viewport.height})`);
      problems.push(...(await captureViewport(browser, base, viewport)));
    }
  } finally {
    await browser.close();
  }

  if (problems.length > 0) {
    console.error(`\n=== ПРОБЛЕМЫ (${problems.length}) ===`);
    for (const p of problems) console.error(`  ✗ ${p}`);
    process.exit(1);
  }

  console.log(`\n=== OK: меню чистое на всех размерах ===\n`);
}

main().catch((err) => {
  console.error("MENU SHOTS FAILED:", err.message ?? err);
  process.exit(1);
});
