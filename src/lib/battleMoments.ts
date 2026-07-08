export type BattleMomentKind = "teamDealt" | "teamReceived" | "knockout";

export interface BattleMomentShot {
  damage: number;
  damageLabel: string;
  dataUrl: string | null;
}

export interface BattleMomentsStore {
  teamDealt: BattleMomentShot | null;
  teamReceived: BattleMomentShot | null;
  knockout: {
    dataUrl: string | null;
    winnerName: string;
    loserName: string;
  } | null;
  pendingCaptures: Array<{ kind: BattleMomentKind; readyAt: number }>;
}

export function createBattleMomentsStore(): BattleMomentsStore {
  return {
    teamDealt: null,
    teamReceived: null,
    knockout: null,
    pendingCaptures: [],
  };
}

function scheduleCapture(
  store: BattleMomentsStore,
  kind: BattleMomentKind,
  readyAt: number,
): void {
  store.pendingCaptures = store.pendingCaptures.filter((p) => p.kind !== kind);
  store.pendingCaptures.push({ kind, readyAt });
}

export function maybeRecordTeamDealt(
  store: BattleMomentsStore,
  damage: number,
  formatDamage: (amount: number) => string,
  now: number,
): void {
  if (damage <= 0.5) return;
  if (!store.teamDealt || damage > store.teamDealt.damage) {
    store.teamDealt = {
      damage,
      damageLabel: formatDamage(damage),
      dataUrl: null,
    };
    scheduleCapture(store, "teamDealt", now + 32);
  }
}

export function maybeRecordTeamReceived(
  store: BattleMomentsStore,
  damage: number,
  formatDamage: (amount: number) => string,
  now: number,
): void {
  if (damage <= 0.5) return;
  if (!store.teamReceived || damage > store.teamReceived.damage) {
    store.teamReceived = {
      damage,
      damageLabel: formatDamage(damage),
      dataUrl: null,
    };
    scheduleCapture(store, "teamReceived", now + 32);
  }
}

export function scheduleKnockoutCapture(
  store: BattleMomentsStore,
  now: number,
  winnerName: string,
  loserName: string,
  delayMs = 420,
): void {
  store.knockout = { dataUrl: null, winnerName, loserName };
  scheduleCapture(store, "knockout", now + delayMs);
}

/** Снимок после полного overlay (лица уже нарисованы). */
export function hasDueCaptures(
  store: BattleMomentsStore,
  now: number,
): boolean {
  return store.pendingCaptures.some((p) => now >= p.readyAt);
}

export function processPendingCaptures(
  store: BattleMomentsStore,
  canvas: HTMLCanvasElement,
  now: number,
): boolean {
  const next = store.pendingCaptures.find((p) => now >= p.readyAt);
  if (!next) return false;

  let dataUrl: string;
  try {
    dataUrl = canvas.toDataURL("image/jpeg", 0.82);
  } catch {
    store.pendingCaptures = store.pendingCaptures.filter((p) => p !== next);
    return false;
  }

  if (next.kind === "teamDealt" && store.teamDealt) {
    store.teamDealt.dataUrl = dataUrl;
  } else if (next.kind === "teamReceived" && store.teamReceived) {
    store.teamReceived.dataUrl = dataUrl;
  } else if (next.kind === "knockout" && store.knockout) {
    store.knockout.dataUrl = dataUrl;
  }

  store.pendingCaptures = store.pendingCaptures.filter((p) => p !== next);
  return true;
}
