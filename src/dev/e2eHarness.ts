/** Хук для браузерных smoke/e2e — Puppeteer ждёт window.__RAGDOLL_E2E__.phase === "ok". */

export type E2EPhase = "idle" | "running" | "ok" | "fail";

export interface RagdollE2EApi {
  scenario: string;
  phase: E2EPhase;
  metrics: Record<string, unknown>;
  error: string | null;
  setPhase: (phase: E2EPhase) => void;
  ok: (metrics?: Record<string, unknown>) => void;
  fail: (message: string) => void;
}

declare global {
  interface Window {
    __RAGDOLL_E2E__?: RagdollE2EApi;
  }
}

let harness: RagdollE2EApi | null = null;

export function getE2EScenario(): string | null {
  if (typeof window === "undefined") return null;
  return new URLSearchParams(window.location.search).get("e2e");
}

export function initE2EHarness(): RagdollE2EApi | null {
  if (typeof window === "undefined") return null;
  const scenario = getE2EScenario();
  if (!scenario) return null;

  if (!harness) {
    harness = {
      scenario,
      phase: "idle",
      metrics: {},
      error: null,
      setPhase(phase) {
        this.phase = phase;
      },
      ok(metrics) {
        if (metrics) Object.assign(this.metrics, metrics);
        this.phase = "ok";
      },
      fail(message) {
        this.error = message;
        this.phase = "fail";
        console.error("[e2e]", scenario, message);
      },
    };
    window.__RAGDOLL_E2E__ = harness;
  }
  return harness;
}

export function e2eApi(): RagdollE2EApi | null {
  return harness ?? window.__RAGDOLL_E2E__ ?? null;
}

export function e2eOk(metrics?: Record<string, unknown>): void {
  e2eApi()?.ok(metrics);
}

export function e2eFail(message: string): void {
  e2eApi()?.fail(message);
}

export function e2eSetPhase(phase: E2EPhase): void {
  e2eApi()?.setPhase(phase);
}

export function e2eMatches(scenario: string): boolean {
  return getE2EScenario() === scenario;
}
