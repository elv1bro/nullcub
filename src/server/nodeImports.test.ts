import { describe, expect, it } from "vitest";
import { spawn } from "node:child_process";
import { createArenaWalls } from "@/battle/headlessWalls";
import Matter from "matter-js";

describe("server node imports", () => {
  it("loads headless walls through matter-js shim", () => {
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: 1000, y: 1000 },
    ]);
    const walls = createArenaWalls(bounds);
    expect(walls.bodies).toHaveLength(4);
  });

  it("tsx server entry loads without matter-js named export errors", () =>
    new Promise<void>((resolve, reject) => {
      const proc = spawn(
        "node",
        ["--import", "tsx/esm", "-e", "import('./src/server/main.ts')"],
        {
          env: {
            ...process.env,
            PORT: "8793",
            VITEST: "true",
            // тот же tsconfig, что у `yarn server` — с alias matter-js → shim
            TSX_TSCONFIG_PATH: "tsconfig.server.json",
          },
          stdio: ["ignore", "ignore", "pipe"],
        },
      );

      let stderr = "";
      proc.stderr?.on("data", (chunk) => {
        stderr += String(chunk);
      });

      proc.on("exit", (code) => {
        if (stderr.includes("does not provide an export named")) {
          reject(new Error(stderr));
          return;
        }
        if (code !== 0 && stderr) {
          reject(new Error(stderr));
          return;
        }
        resolve();
      });
    }));
});
