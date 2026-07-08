import type { PropsWithChildren } from "react";
import { useTranslation } from "@/settings/SettingsContext";

interface Props extends PropsWithChildren {
  /** Компактный вариант в боковой панели */
  compact?: boolean;
}

export function MenuTitle({ compact }: Props) {
  const t = useTranslation();
  return (
    <header
      className={[
        "menu-title-pop menu-title-intro shrink-0",
        compact ? "text-left pb-2" : "text-center pt-4 pb-2 px-4",
      ].join(" ")}
    >
      <h1
        className={[
          "font-display uppercase leading-tight tracking-wide",
          compact ? "text-2xl md:text-3xl" : "text-4xl md:text-5xl",
        ].join(" ")}
      >
        <span className="text-white">{t.game.title}</span>{" "}
        <span className="menu-title-accent">{t.game.titleAccent}</span>
      </h1>
      <p
        className={[
          "font-ui text-gray-400/90 mt-2 leading-relaxed",
          compact ? "text-sm max-w-none" : "text-sm md:text-base max-w-lg mx-auto",
        ].join(" ")}
      >
        {t.game.subtitle}
      </p>
    </header>
  );
}
