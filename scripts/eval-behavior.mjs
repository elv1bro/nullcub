#!/usr/bin/env node
/**
 * Быстрая оценка поведения для агентов (без DOM / Chrome).
 * Запускает evaluateBehavior() через vitest (нужен Vite-резолв matter-js).
 *
 * Usage:
 *   yarn eval:behavior
 *
 * Exit 0 → ok; ≠0 → сломано.
 * Отчёт: test-artifacts/behavior-report.json
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const outFile = resolve(root, "test-artifacts/behavior-report.json");

const result = spawnSync(
  "yarn",
  ["vitest", "run", "src/lib/behaviorEval.test.ts", "--reporter=dot"],
  {
    cwd: root,
    env: { ...process.env, WRITE_BEHAVIOR_REPORT: "1" },
    encoding: "utf8",
    stdio: ["inherit", "pipe", "pipe"],
  },
);

const combined = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
// Print vitest stdout (includes our formatted summary from the test)
process.stdout.write(result.stdout ?? "");
if (result.stderr) process.stderr.write(result.stderr);

if (!existsSync(outFile)) {
  console.error("\nbehavior-report.json was not written. Vitest may have crashed.");
  if (combined.trim()) console.error(combined.slice(-2000));
  process.exit(result.status === 0 ? 1 : result.status ?? 1);
}

const report = JSON.parse(readFileSync(outFile, "utf8"));
const failed = (report.checks ?? []).filter((c) => !c.ok);

console.log(`\nReport: ${outFile}`);
console.log(`Duration: ${report.durationMs}ms`);
console.log(report.ok ? "\n=== OK: behavior ===\n" : "\n=== FAIL: behavior ===\n");

if (!report.ok) {
  console.error("Failed:", failed.map((f) => f.id).join(", "));
  process.exit(1);
}

process.exit(result.status === 0 ? 0 : result.status ?? 1);
