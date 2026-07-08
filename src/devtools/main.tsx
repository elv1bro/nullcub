import "@unocss/reset/eric-meyer.css";
import ReactDOM from "react-dom/client";
import "virtual:uno.css";
import { DevHubShell } from "./DevHubShell";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <DevHubShell />,
);
