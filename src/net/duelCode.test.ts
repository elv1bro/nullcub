import { describe, expect, it } from "vitest";
import {
  buildDuelCode,
  parseDuelCode,
  randomDuelSecret,
} from "./wsClient";

describe("duel code secret", () => {
  it("round-trips server|room|secret", () => {
    const secret = randomDuelSecret();
    expect(secret).toMatch(/^[a-f0-9]{16}$/);
    const code = buildDuelCode("ws://127.0.0.1:8787", "roomabc", secret);
    const parsed = parseDuelCode(code);
    expect(parsed).toEqual({
      server: "ws://127.0.0.1:8787",
      room: "roomabc",
      secret,
    });
  });

  it("rejects legacy codes without secret", () => {
    const legacy = btoa("ws://127.0.0.1:8787|oldroom")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    expect(parseDuelCode(legacy)).toBeNull();
  });

  it("rejects short/invalid secrets", () => {
    const bad = btoa("ws://127.0.0.1:8787|room|short")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    expect(parseDuelCode(bad)).toBeNull();
  });
});
