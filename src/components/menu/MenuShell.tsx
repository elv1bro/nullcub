import { MenuArenaBg } from "./MenuArenaBg";
import { MenuSparkField } from "./MenuSparkField";
import type { PropsWithChildren } from "react";
import { useEffect } from "react";

interface Props extends PropsWithChildren {
  accentColor?: string;
  accentSecondary?: string;
}

/** Оболочка меню: фон арены, accent-токены, контент. */
export function MenuShell({
  children,
  accentColor = "#38bdf8",
  accentSecondary = "#f87171",
}: Props) {
  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty("--menu-accent", accentColor);
    root.style.setProperty("--menu-accent-secondary", accentSecondary);
    return () => {
      root.style.removeProperty("--menu-accent");
      root.style.removeProperty("--menu-accent-secondary");
    };
  }, [accentColor, accentSecondary]);

  return (
    <div className="relative h-full min-h-screen overflow-hidden menu-shell-bg flex flex-col">
      <MenuArenaBg />
      <MenuSparkField accentColor={accentColor} />
      <div
        className="fixed inset-0 pointer-events-none z-1"
        style={{
          boxShadow: "inset 0 0 100px rgba(0,0,0,0.5)",
        }}
      />
      <div className="relative z-10 flex flex-col flex-1 min-h-0">{children}</div>
    </div>
  );
}
