import {
  formatBenchmarkMarkdown,
  runAiBenchmarkInBrowser,
} from "@/battle/aiBenchmark";

const rounds = Number(new URLSearchParams(location.search).get("rounds") ?? 3);
const report = runAiBenchmarkInBrowser(rounds);

window.__AI_BENCHMARK__ = report;

const out = document.getElementById("out");
if (out) out.textContent = formatBenchmarkMarkdown(report);

export { report };
