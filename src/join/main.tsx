import "@unocss/reset/eric-meyer.css";
import ReactDOM from "react-dom/client";
import "virtual:uno.css";
import "@/styles/menu.css";
import { registerDefaultItems } from "@/items";
import { Renderer } from "@/components/Renderer";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { PlayerProfileProvider } from "@/player/PlayerProfileContext";
import { SettingsProvider } from "@/settings/SettingsContext";
import { JoinBattle } from "./JoinBattle";

registerDefaultItems();

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <SettingsProvider>
    <PlayerProfileProvider>
      <Renderer engine={{ gravity: BATTLE_GRAVITY }} runner={{ enabled: false }}>
        <JoinBattle />
      </Renderer>
    </PlayerProfileProvider>
  </SettingsProvider>,
);
