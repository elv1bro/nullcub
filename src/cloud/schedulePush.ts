/** Лёгкий модуль без импорта стораджей — чтобы не ловить циклы. */

let pushTimer: ReturnType<typeof setTimeout> | null = null;

export function scheduleCloudPush(): void {
  if (typeof window === "undefined") return;
  if (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY) {
    return;
  }
  if (pushTimer) clearTimeout(pushTimer);
  pushTimer = setTimeout(() => {
    pushTimer = null;
    void import("./cloudProgress")
      .then((m) => m.pushCloudProgress())
      .catch(() => undefined);
  }, 900);
}
