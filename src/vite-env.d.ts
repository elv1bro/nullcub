/// <reference types="vite/client" />

// Сборка matter-js без типов — используем декларации основного пакета.
declare module "matter-js/build/matter.js" {
  import Matter = require("matter-js");
  export = Matter;
}
