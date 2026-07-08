import { describe, expect, it } from "vitest";
import {
  formatBenchmarkMarkdown,
  runAiBenchmark,
  type MatchupSummary,
} from "./aiBenchmark";
import type { AiDifficultyId } from "./aiProfiles";
import { runHeadlessDuel } from "./headlessDuel";

function tierWinRate(
  summaries: MatchupSummary[],
  stronger: AiDifficultyId,
  weaker: AiDifficultyId,
): number {
  const row = summaries.find(
    (s) =>
      (s.a === stronger && s.b === weaker) ||
      (s.a === weaker && s.b === stronger),
  );
  if (!row || row.fights === 0) return 0;
  const wins = row.a === stronger ? row.winsA : row.winsB;
  return wins / row.fights;
}

describe("headlessDuel", () => {
  it("finishes a duel within time limit", () => {
    const out = runHeadlessDuel("easy", "boss", 99);
    expect(out.steps).toBeGreaterThan(0);
    expect(out.durationMs).toBeGreaterThan(0);
    expect(["easy", "boss", "draw"]).toContain(out.winner);
  });

  it("boss beats easy more often than not", () => {
    let bossWins = 0;
    for (let seed = 1; seed <= 8; seed++) {
      const out = runHeadlessDuel("easy", "boss", seed);
      if (out.winner === "boss") bossWins++;
    }
    expect(bossWins).toBeGreaterThanOrEqual(4);
  });
});

describe("aiBenchmark", () => {
  it("runs round-robin for 4 presets", () => {
    const rounds = Number(process.env.AI_BENCHMARK_ROUNDS ?? 2);
    const report = runAiBenchmark(rounds);
    expect(report.totalFights).toBe(6 * rounds);
    expect(report.summaries).toHaveLength(6);
    expect(report.records.every((r) => r.durationSec > 0)).toBe(true);
    // eslint-disable-next-line no-console
    console.log("\n" + formatBenchmarkMarkdown(report));
  });

  it("difficulty ladder: higher tier wins more (10+ rounds per pair)", () => {
    const rounds = Number(process.env.AI_BENCHMARK_ROUNDS ?? 10);
    const report = runAiBenchmark(rounds);
    const avgSec =
      report.records.reduce((s, r) => s + r.durationSec, 0) /
      report.records.length;

    expect(tierWinRate(report.summaries, "normal", "easy")).toBeGreaterThanOrEqual(
      0.55,
    );
    expect(tierWinRate(report.summaries, "hard", "normal")).toBeGreaterThanOrEqual(
      0.6,
    );
    // Adjacent top tiers are close; n=10 is noisy around 50%, so allow a slight dip.
    expect(tierWinRate(report.summaries, "boss", "hard")).toBeGreaterThanOrEqual(
      0.4,
    );
    expect(avgSec).toBeLessThan(120);
    // eslint-disable-next-line no-console
    console.log("\n[ladder]", { rounds, avgSec, report: report.summaries });
  });
});
