import { beforeEach, describe, expect, it, vi } from "vitest";
import { BOUNCER_CHAPTERS } from "@/campaign/bouncer";
import {
  getMaxUnlockedOrder,
  isChapterUnlocked,
  resetCampaignProgress,
  unlockAfterWin,
} from "@/campaign/progress";

describe("campaign progress", () => {
  beforeEach(() => {
    const store = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => {
        store.set(key, value);
      },
      removeItem: (key: string) => {
        store.delete(key);
      },
    });
    resetCampaignProgress();
  });

  it("starts with first chapter only", () => {
    expect(getMaxUnlockedOrder()).toBe(0);
    expect(isChapterUnlocked(0)).toBe(true);
    expect(isChapterUnlocked(1)).toBe(false);
  });

  it("unlocks next chapter after win", () => {
    unlockAfterWin("bard");
    expect(getMaxUnlockedOrder()).toBe(1);
    expect(isChapterUnlocked(1)).toBe(true);
    expect(isChapterUnlocked(2)).toBe(false);
  });

  it("does not skip chapters", () => {
    unlockAfterWin("boss");
    expect(getMaxUnlockedOrder()).toBe(BOUNCER_CHAPTERS.length - 1);
  });
});
