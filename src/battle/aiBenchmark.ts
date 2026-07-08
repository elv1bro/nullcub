import type { AiDifficultyId } from "./aiProfiles";
import { AI_DIFFICULTY_ORDER } from "./aiProfiles";
import { runHeadlessDuel, type HeadlessDuelOutcome } from "./headlessDuel";

export interface MatchupKey {
  a: AiDifficultyId;
  b: AiDifficultyId;
}

export interface MatchRecord {
  matchup: MatchupKey;
  fight: number;
  winner: AiDifficultyId | "draw";
  durationMs: number;
  durationSec: number;
  hpLeft: HeadlessDuelOutcome["hpLeft"];
}

export interface MatchupSummary {
  a: AiDifficultyId;
  b: AiDifficultyId;
  fights: number;
  winsA: number;
  winsB: number;
  draws: number;
  avgDurationSec: number;
  minDurationSec: number;
  maxDurationSec: number;
}

export interface AiBenchmarkReport {
  roundsPerMatchup: number;
  records: MatchRecord[];
  summaries: MatchupSummary[];
  totalFights: number;
  totalDurationSec: number;
}

function matchupKey(a: AiDifficultyId, b: AiDifficultyId): string {
  return a <= b ? `${a}|${b}` : `${b}|${a}`;
}

function pairKeys(): MatchupKey[] {
  const pairs: MatchupKey[] = [];
  for (let i = 0; i < AI_DIFFICULTY_ORDER.length; i++) {
    for (let j = i + 1; j < AI_DIFFICULTY_ORDER.length; j++) {
      pairs.push({ a: AI_DIFFICULTY_ORDER[i]!, b: AI_DIFFICULTY_ORDER[j]! });
    }
  }
  return pairs;
}

export function runAiBenchmark(roundsPerMatchup = 3): AiBenchmarkReport {
  const records: MatchRecord[] = [];
  let seed = 10_001;

  for (const { a, b } of pairKeys()) {
    for (let fight = 1; fight <= roundsPerMatchup; fight++) {
      // Чётные раунды меняют стороны арены
      const left = fight % 2 === 1 ? a : b;
      const right = fight % 2 === 1 ? b : a;
      const outcome = runHeadlessDuel(left, right, seed++);
      records.push({
        matchup: { a, b },
        fight,
        winner: outcome.winner,
        durationMs: outcome.durationMs,
        durationSec: Math.round(outcome.durationMs / 100) / 10,
        hpLeft: outcome.hpLeft,
      });
    }
  }

  const grouped = new Map<string, MatchRecord[]>();
  for (const rec of records) {
    const key = matchupKey(rec.matchup.a, rec.matchup.b);
    const list = grouped.get(key) ?? [];
    list.push(rec);
    grouped.set(key, list);
  }

  const summaries: MatchupSummary[] = pairKeys().map(({ a, b }) => {
    const key = matchupKey(a, b);
    const fights = grouped.get(key) ?? [];
    let winsA = 0;
    let winsB = 0;
    let draws = 0;
    const durations = fights.map((f) => f.durationSec);

    for (const f of fights) {
      if (f.winner === "draw") draws++;
      else if (f.winner === a) winsA++;
      else if (f.winner === b) winsB++;
    }

    const avg = durations.length
      ? durations.reduce((s, d) => s + d, 0) / durations.length
      : 0;

    return {
      a,
      b,
      fights: fights.length,
      winsA,
      winsB,
      draws,
      avgDurationSec: Math.round(avg * 10) / 10,
      minDurationSec: durations.length ? Math.min(...durations) : 0,
      maxDurationSec: durations.length ? Math.max(...durations) : 0,
    };
  });

  const totalDurationSec = records.reduce((s, r) => s + r.durationSec, 0);

  return {
    roundsPerMatchup,
    records,
    summaries,
    totalFights: records.length,
    totalDurationSec: Math.round(totalDurationSec * 10) / 10,
  };
}

export function formatBenchmarkMarkdown(report: AiBenchmarkReport): string {
  const lines: string[] = [
    `## AI benchmark (${report.totalFights} боёв, ${report.totalDurationSec}s симуляции)`,
    "",
    "### Сводка по парам",
    "",
    "| Пара | Бои | Побед A | Побед B | Ничьи | Ср. время | Min | Max |",
    "|------|-----|---------|---------|-------|-----------|-----|-----|",
  ];

  for (const s of report.summaries) {
    lines.push(
      `| **${s.a}** vs **${s.b}** | ${s.fights} | ${s.winsA} | ${s.winsB} | ${s.draws} | ${s.avgDurationSec}s | ${s.minDurationSec}s | ${s.maxDurationSec}s |`,
    );
  }

  lines.push("", "### Каждый бой", "", "| # | Пара | Раунд | Победитель | Время | HP осталось |", "|---|------|-------|------------|-------|-------------|");

  report.records.forEach((r, idx) => {
    const hp = `${r.matchup.a}:${r.hpLeft[r.matchup.a] ?? "?"}, ${r.matchup.b}:${r.hpLeft[r.matchup.b] ?? "?"}`;
    lines.push(
      `| ${idx + 1} | ${r.matchup.a} vs ${r.matchup.b} | ${r.fight} | **${r.winner}** | ${r.durationSec}s | ${hp} |`,
    );
  });

  return lines.join("\n");
}

/** Для headless Chrome / window hook (browser only). */
export function runAiBenchmarkInBrowser(roundsPerMatchup = 3): AiBenchmarkReport {
  return runAiBenchmark(roundsPerMatchup);
}

declare global {
  interface Window {
    runAiBenchmark?: typeof runAiBenchmarkInBrowser;
    __AI_BENCHMARK__?: AiBenchmarkReport;
  }
}

if (typeof window !== "undefined") {
  window.runAiBenchmark = runAiBenchmarkInBrowser;
}
