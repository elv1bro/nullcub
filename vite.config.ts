//

import React from "@vitejs/plugin-react";
import { resolve } from "node:path";
import UnoCSS from "unocss/vite";
import { defineConfig } from "vite";

//

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: 5199,
    strictPort: true,
  },
  preview: {
    host: "127.0.0.1",
    port: 5199,
    strictPort: true,
  },
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        join: resolve(__dirname, "join.html"),
        devtools: resolve(__dirname, "devtools.html"),
      },
    },
  },
  resolve: {
    alias: [
      {
        find: /^matter-js$/,
        replacement: resolve(__dirname, "./src/matter.ts"),
      },
      {
        find: "@",
        replacement: resolve(__dirname, "./src"),
      },
      {
        find: /^@1\.(.*)/,
        replacement: resolve(__dirname, "./@1/$1"),
      },
    ],
  },
  plugins: [React(), UnoCSS()],
  test: {
    setupFiles: ["src/test/setupAudio.ts"],
  },
});
