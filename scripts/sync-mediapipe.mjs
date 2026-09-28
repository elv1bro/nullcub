#!/usr/bin/env node
/**
 * Кладёт MediaPipe рядом с игрой, чтобы браузер игрока не ходил на чужие CDN.
 *
 * - wasm копируется из node_modules (версия закреплена в package.json,
 *   вместо незакреплённого @latest с jsdelivr);
 * - модель face_landmarker скачивается один раз и коммитится в репозиторий.
 *
 * Запуск: yarn mediapipe:sync (вызывается автоматически из dev и build).
 */

import { createRequire } from "node:module";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const wasmOut = join(root, "public", "mediapipe");
const modelOut = join(root, "public", "models");

/**
 * FilesetResolver.forVisionTasks просит simd-вариант, а на старых движках
 * откатывается на nosimd. Вариант *_module_internal нужен только для ESM-воркера,
 * который мы не используем, поэтому не копируем — это лишние 11 МБ.
 */
const WASM_FILES = [
  "vision_wasm_internal.js",
  "vision_wasm_internal.wasm",
  "vision_wasm_nosimd_internal.js",
  "vision_wasm_nosimd_internal.wasm",
];

const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";
const MODEL_FILE = "face_landmarker.task";

function sameSize(from, to) {
  return existsSync(to) && statSync(to).size === statSync(from).size;
}

// В exports пакета нет "./package.json", поэтому идём от главного модуля.
const pkgDir = dirname(require.resolve("@mediapipe/tasks-vision"));
const version = JSON.parse(
  readFileSync(join(pkgDir, "package.json"), "utf8"),
).version;

mkdirSync(wasmOut, { recursive: true });
let copied = 0;
for (const file of WASM_FILES) {
  const from = join(pkgDir, "wasm", file);
  const to = join(wasmOut, file);
  if (sameSize(from, to)) continue;
  copyFileSync(from, to);
  copied += 1;
}
writeFileSync(
  join(wasmOut, "VERSION.txt"),
  `@mediapipe/tasks-vision ${version}\nСгенерировано scripts/sync-mediapipe.mjs — не коммитить.\n`,
);

mkdirSync(modelOut, { recursive: true });
const modelPath = join(modelOut, MODEL_FILE);
if (!existsSync(modelPath)) {
  console.log(`mediapipe: качаю модель ${MODEL_FILE}…`);
  const res = await fetch(MODEL_URL);
  if (!res.ok) throw new Error(`не скачалась модель: HTTP ${res.status}`);
  writeFileSync(modelPath, Buffer.from(await res.arrayBuffer()));
}

console.log(
  `mediapipe: wasm ${copied === 0 ? "актуален" : `обновлён (${copied} файлов)`}` +
    `, модель ${(statSync(modelPath).size / 1024 / 1024).toFixed(1)} МБ, версия ${version}`,
);
