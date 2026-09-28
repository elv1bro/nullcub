/** Скрытый каталог «Тесты»: `?tests` / `?debug` / `?lab=tests`, или разлок кликами по версии.
 * Не путать со StrikeLab (`?lab=1`). */

const STORAGE_KEY = "ragdoll-lab-unlocked";

export function isLabQuery(): boolean {
  if (typeof window === "undefined") return false;
  const q = new URLSearchParams(window.location.search);
  if (q.has("tests") || q.has("debug")) return true;
  const lab = q.get("lab");
  // `?lab` / `?lab=tests` / `?lab=catalog` — каталог; `?lab=1` — StrikeLab
  return lab === "" || lab === "tests" || lab === "catalog" || lab === "true";
}

export function isLabUnlocked(): boolean {
  if (typeof window === "undefined") return false;
  if (isLabQuery()) return true;
  try {
    return sessionStorage.getItem(STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

export function unlockLab(): void {
  try {
    sessionStorage.setItem(STORAGE_KEY, "1");
  } catch {
    /* ignore */
  }
}

/** Сколько кликов по версии в футере нужно для разлока. */
export const LAB_UNLOCK_CLICKS = 7;
