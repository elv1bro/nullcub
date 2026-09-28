import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { evaluateBehavior, type BehaviorReport } from "./behaviorEval";

function formatCheck(c: BehaviorReport["checks"][number]): string {
  const mark = c.ok ? "✓" : "✗";
  const cmp =
    c.cmp === "lt"
      ? `< ${c.limit}`
      : c.cmp === "lte"
        ? `≤ ${c.limit}`
        : c.cmp === "gt"
          ? `> ${c.limit}`
          : `≥ ${c.limit}`;
  return `  ${mark} ${c.id}: ${c.value}${c.unit ? c.unit : ""} (need ${cmp})${c.detail ? ` — ${c.detail}` : ""}`;
}

describe("behaviorEval", () => {
  it("produces a report where all checks pass on a healthy build", () => {
    const report = evaluateBehavior();

    if (process.env.WRITE_BEHAVIOR_REPORT === "1") {
      const outDir = resolve(process.cwd(), "test-artifacts");
      const outFile = resolve(outDir, "behavior-report.json");
      mkdirSync(outDir, { recursive: true });
      writeFileSync(outFile, JSON.stringify(report, null, 2) + "\n", "utf8");
      console.log("\n=== Behavior eval ===\n");
      for (const c of report.checks) {
        console.log(formatCheck(c));
      }
    }

    const failed = report.checks.filter((c) => !c.ok);
    expect(
      failed,
      failed.map((f) => `${f.id}=${f.value}`).join(", "),
    ).toEqual([]);
    expect(report.ok).toBe(true);
    expect(report.checks.length).toBeGreaterThanOrEqual(8);
  }, 120_000);
});
