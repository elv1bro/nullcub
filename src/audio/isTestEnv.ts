/** Vitest / `MODE=test` — тихий режим без звука. */
export function isTestEnv(): boolean {
  if (typeof process !== "undefined" && process.env["VITEST"] === "true") {
    return true;
  }
  return typeof import.meta !== "undefined" && import.meta.env?.MODE === "test";
}
