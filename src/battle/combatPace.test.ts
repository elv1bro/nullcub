import { describe, expect, it } from "vitest";
import { runHeadlessDuel } from "./headlessDuel";

/** Feel QC: бои не должны тянуться в «кашу» и не должны заканчиваться мгновенно. */
describe("combat:pace", () => {
  it("easy vs hard median duration stays in an action window", () => {
    const durations: number[] = [];
    for (let seed = 1; seed <= 8; seed++) {
      const out = runHeadlessDuel("easy", "hard", seed);
      durations.push(out.durationMs / 1000);
    }
    durations.sort((a, b) => a - b);
    const mid = Math.floor(durations.length / 2);
    const median =
      durations.length % 2 === 0
        ? (durations[mid - 1]! + durations[mid]!) / 2
        : durations[mid]!;

    expect(median).toBeGreaterThanOrEqual(8);
    expect(median).toBeLessThanOrEqual(55);
    // eslint-disable-next-line no-console
    console.log("[combat:pace]", { median, durations });
  });
});
