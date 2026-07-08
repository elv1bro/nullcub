//

import "@unocss/reset/eric-meyer.css";
import { StrictMode } from "react";
import ReactDOM from "react-dom/client";
import "virtual:uno.css";
import "@/styles/menu.css";
import { registerDefaultItems } from "@/items";
import { initE2EHarness } from "@/dev/e2eHarness";
import App from "./App";

registerDefaultItems();
initE2EHarness();

//

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <StrictMode>
    <App />
  </StrictMode>
);
