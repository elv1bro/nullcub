import { GameContext } from "@/GameContext";
import { SubMenuScreen } from "@/components/menu/SubMenuScreen";
import { useTranslation } from "@/settings/SettingsContext";
import { useContext, type ComponentPropsWithoutRef } from "react";

export default CampaignMenu;

export function CampaignMenu({ ...props }: ComponentPropsWithoutRef<"section">) {
  const { sendN } = useContext(GameContext);
  const t = useTranslation();

  return (
    <SubMenuScreen title={t.campaign.title} {...props}>
      <ul className="vstack gap-3">
        <li>
          <button type="button" className="menu-nav-btn" onClick={sendN("LOCAL_CAMPAIGN")}>
            {t.campaign.local}
          </button>
          <p className="font-ui text-xs text-gray-400 text-center mt-2">
            {t.campaign.localHint}
          </p>
        </li>
        <li>
          <button type="button" className="menu-nav-btn" disabled onClick={sendN("MULTIPLAYER")}>
            {t.campaign.online}
          </button>
          <p className="font-ui text-xs text-gray-500 text-center mt-2 uppercase">
            {t.campaign.onlineSoon}
          </p>
        </li>
      </ul>
    </SubMenuScreen>
  );
}
