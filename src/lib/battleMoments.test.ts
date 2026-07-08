import { describe, expect, it, vi } from "vitest";
import {
  createBattleMomentsStore,
  hasDueCaptures,
  maybeRecordTeamDealt,
  maybeRecordTeamReceived,
  processPendingCaptures,
  scheduleKnockoutCapture,
} from "./battleMoments";

describe("battleMoments", () => {
  const format = (n: number) => `−${n} ♥`;

  it("keeps only the highest dealt hit", () => {
    const store = createBattleMomentsStore();
    maybeRecordTeamDealt(store, 12, format, 100);
    maybeRecordTeamDealt(store, 8, format, 200);
    maybeRecordTeamDealt(store, 40, format, 300);

    expect(store.teamDealt?.damage).toBe(40);
    expect(store.teamDealt?.damageLabel).toBe("−40 ♥");
    expect(store.pendingCaptures.some((p) => p.kind === "teamDealt")).toBe(true);
  });

  it("keeps only the highest received hit", () => {
    const store = createBattleMomentsStore();
    maybeRecordTeamReceived(store, 5, format, 100);
    maybeRecordTeamReceived(store, 22, format, 200);

    expect(store.teamReceived?.damage).toBe(22);
  });

  it("stores knockout winner and loser names", () => {
    const store = createBattleMomentsStore();
    scheduleKnockoutCapture(store, 0, "Барди", "Бот", 0);
    expect(store.knockout?.winnerName).toBe("Барди");
    expect(store.knockout?.loserName).toBe("Бот");
    expect(hasDueCaptures(store, 1)).toBe(true);
  });

  it("captures one due screenshot per call", () => {
    const store = createBattleMomentsStore();
    maybeRecordTeamDealt(store, 10, format, 0);
    scheduleKnockoutCapture(store, 0, "Hero", "Enemy", 0);

    const canvas = {
      toDataURL: vi.fn(() => "data:image/jpeg;base64,abc"),
    } as unknown as HTMLCanvasElement;

    expect(processPendingCaptures(store, canvas, 999)).toBe(true);
    expect(store.teamDealt?.dataUrl).toBe("data:image/jpeg;base64,abc");
    expect(store.knockout?.dataUrl).toBeNull();
    expect(store.pendingCaptures).toHaveLength(1);

    expect(processPendingCaptures(store, canvas, 999)).toBe(true);
    expect(store.knockout?.dataUrl).toBe("data:image/jpeg;base64,abc");
    expect(store.pendingCaptures).toHaveLength(0);
  });
});
