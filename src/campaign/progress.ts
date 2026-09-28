import { scheduleCloudPush } from "@/cloud/schedulePush";
import { loadVersioned, saveVersioned } from "@/lib/storageSchema";
import {
  BOUNCER_CAMPAIGN_ID,
  BOUNCER_CHAPTERS,
  type BouncerChapterId,
} from "./bouncer";

const STORAGE_KEY = "ragdoll-bouncer-progress";
const SCHEMA_VERSION = 1;

type ProgressStore = Record<string, number>;

function loadStore(): ProgressStore {
  return loadVersioned<ProgressStore>({
    key: STORAGE_KEY,
    version: SCHEMA_VERSION,
    migrate: (data) => {
      if (typeof data !== "object" || data === null || Array.isArray(data)) {
        return null;
      }
      const store: ProgressStore = {};
      for (const [k, v] of Object.entries(data)) {
        if (typeof v === "number" && Number.isFinite(v)) store[k] = v;
      }
      return store;
    },
    fallback: () => ({}),
  });
}

function saveStore(store: ProgressStore): void {
  saveVersioned(STORAGE_KEY, SCHEMA_VERSION, store);
}

export function replaceCampaignProgress(store: ProgressStore): void {
  saveStore(store);
}

/** Максимальный order открытой главы (0 = только первая). */
export function getMaxUnlockedOrder(campaignId = BOUNCER_CAMPAIGN_ID): number {
  const store = loadStore();
  const value = store[campaignId];
  if (typeof value !== "number" || Number.isNaN(value)) return 0;
  return Math.max(0, Math.min(value, BOUNCER_CHAPTERS.length - 1));
}

export function isChapterUnlocked(
  order: number,
  campaignId = BOUNCER_CAMPAIGN_ID,
): boolean {
  return order <= getMaxUnlockedOrder(campaignId);
}

export function unlockAfterWin(
  chapterId: BouncerChapterId,
  campaignId = BOUNCER_CAMPAIGN_ID,
): void {
  const chapter = BOUNCER_CHAPTERS.find((c) => c.id === chapterId);
  if (!chapter) return;

  const store = loadStore();
  const current = getMaxUnlockedOrder(campaignId);
  const next = Math.min(
    BOUNCER_CHAPTERS.length - 1,
    Math.max(current, chapter.order + 1),
  );
  store[campaignId] = next;
  saveStore(store);
  scheduleCloudPush();
}

export function resetCampaignProgress(campaignId = BOUNCER_CAMPAIGN_ID): void {
  const store = loadStore();
  delete store[campaignId];
  saveStore(store);
  scheduleCloudPush();
}
