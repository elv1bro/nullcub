import { afterEach, describe, expect, it, vi } from "vitest";
import {
  getAppPlatform,
  platformSkipsWebAuthGate,
} from "./identity";

describe("platform identity", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("defaults to web in node (no window)", () => {
    expect(getAppPlatform()).toBe("web");
    expect(platformSkipsWebAuthGate("web")).toBe(false);
  });

  it("steam/electron/local skip web auth gate", () => {
    expect(platformSkipsWebAuthGate("steam")).toBe(true);
    expect(platformSkipsWebAuthGate("electron")).toBe(true);
    expect(platformSkipsWebAuthGate("local")).toBe(true);
  });

  it("reads window.__RAGDOLL_PLATFORM__ for steam builds", () => {
    vi.stubGlobal("window", { __RAGDOLL_PLATFORM__: "steam" });
    expect(getAppPlatform()).toBe("steam");
    expect(platformSkipsWebAuthGate()).toBe(true);
  });
});
