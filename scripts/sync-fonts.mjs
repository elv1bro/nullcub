#!/usr/bin/env node
/**
 * Копирует woff2 из пакетов @fontsource-variable в public/fonts и генерирует
 * public/fonts/fonts.css с оригинальными именами семейств (Rubik, Unbounded,
 * Caveat), которые используются в стилях.
 *
 * Шрифты обязаны раздаваться со своего домена: загрузка с fonts.googleapis.com
 * передаёт IP посетителя в Google без согласия (LG München I, 3 O 17493/20).
 *
 * Запуск: yarn fonts:sync
 */

import { createRequire } from "node:module";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "public", "fonts");

const FAMILIES = [
  { pkg: "@fontsource-variable/rubik", family: "Rubik", prefix: "rubik" },
  {
    pkg: "@fontsource-variable/unbounded",
    family: "Unbounded",
    prefix: "unbounded",
  },
  { pkg: "@fontsource-variable/caveat", family: "Caveat", prefix: "caveat" },
];

/** Игра локализована на en/ru; остальные диапазоны падают на системный шрифт. */
const SUBSETS = ["latin", "latin-ext", "cyrillic", "cyrillic-ext"];

function packageDir(pkg) {
  return dirname(require.resolve(`${pkg}/package.json`));
}

function parseFaces(css) {
  const faces = [];
  for (const [, body] of css.matchAll(/@font-face\s*\{([\s\S]*?)\}/g)) {
    const file = body.match(/url\(\.\/files\/([^)]+\.woff2)\)/)?.[1];
    const range = body.match(/unicode-range:\s*([^;]+);/)?.[1];
    const weight = body.match(/font-weight:\s*([^;]+);/)?.[1] ?? "400";
    if (file && range) faces.push({ file, range: range.trim(), weight: weight.trim() });
  }
  return faces;
}

function subsetOf(file, prefix) {
  return file.slice(prefix.length + 1, file.indexOf("-wght-"));
}

mkdirSync(outDir, { recursive: true });

const blocks = [];
let copied = 0;

for (const { pkg, family, prefix } of FAMILIES) {
  const dir = packageDir(pkg);
  const faces = parseFaces(readFileSync(join(dir, "wght.css"), "utf8"));
  const wanted = faces.filter((f) => SUBSETS.includes(subsetOf(f.file, prefix)));

  if (wanted.length === 0) {
    throw new Error(`${pkg}: не найдено ни одного нужного сабсета`);
  }

  for (const face of wanted) {
    copyFileSync(join(dir, "files", face.file), join(outDir, face.file));
    copied += 1;
    blocks.push(
      [
        `/* ${family} · ${subsetOf(face.file, prefix)} */`,
        `@font-face {`,
        `  font-family: "${family}";`,
        `  font-style: normal;`,
        `  font-display: swap;`,
        `  font-weight: ${face.weight};`,
        `  src: url("/fonts/${face.file}") format("woff2-variations");`,
        `  unicode-range: ${face.range};`,
        `}`,
      ].join("\n"),
    );
  }
}

const header = [
  "/*",
  " * Сгенерировано scripts/sync-fonts.mjs — руками не править.",
  " * Источник: пакеты @fontsource-variable (шрифты под SIL Open Font License).",
  " * Файлы раздаются со своего домена: внешних запросов за шрифтами быть не должно.",
  " */",
  "",
].join("\n");

writeFileSync(join(outDir, "fonts.css"), `${header}${blocks.join("\n\n")}\n`);

console.log(`fonts: ${copied} файлов в public/fonts, ${blocks.length} @font-face`);
