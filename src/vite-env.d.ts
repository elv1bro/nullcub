/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_WS_URL?: string;
  readonly VITE_ENABLE_P2P?: string;
  readonly VITE_ENABLE_LOCAL_FFA?: string;
  /** web | steam | electron | local — влияет на обязательность веб-логина. */
  readonly VITE_PLATFORM?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

// Сборка matter-js без типов — используем декларации основного пакета.
declare module "matter-js/build/matter.js" {
  import Matter = require("matter-js");
  export = Matter;
}
