import { GameContext } from "@/GameContext";
import { MenuShell } from "@/components/menu/MenuShell";
import { MenuBackBar } from "@/components/menu/MenuSlidePanel";
import { useTranslation } from "@/settings/SettingsContext";
import { useContext, type ComponentPropsWithoutRef, type ReactNode } from "react";
import { useKeyPressEvent } from "react-use";

interface SubMenuProps extends ComponentPropsWithoutRef<"section"> {
  title: string;
  children: ReactNode;
}

export function SubMenuScreen({ title, children, ...props }: SubMenuProps) {
  const { sendN } = useContext(GameContext);
  const t = useTranslation();

  useKeyPressEvent("Escape", sendN("BACK"));

  return (
    <MenuShell>
      <div className="flex flex-col h-full min-h-screen p-6 md:p-10">
        <div className="max-w-lg w-full mx-auto menu-glass p-6 md:p-8 menu-panel-enter-right">
          <MenuBackBar label={t.menu.back} onBack={sendN("BACK")} />
          <h2 className="font-display text-2xl uppercase text-center mb-6 text-white">
            {title}
          </h2>
          <section {...props}>{children}</section>
        </div>
      </div>
    </MenuShell>
  );
}
