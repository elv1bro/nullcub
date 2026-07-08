import type { PropsWithChildren } from "react";
import { playMenuSound } from "@/audio";

interface Props extends PropsWithChildren {
  visible: boolean;
}

/** Панель настроек — slide + blur, превью слева остаётся. */
export function MenuSlidePanel({ children, visible }: Props) {
  return (
    <div
      className={["menu-slide-panel menu-glass", visible ? "visible" : "hidden"].join(
        " ",
      )}
      aria-hidden={!visible}
    >
      <div className="menu-glass-inner">{children}</div>
    </div>
  );
}

interface MenuHomeProps extends PropsWithChildren {
  visible: boolean;
}

export function MenuHomeLayer({ children, visible }: MenuHomeProps) {
  return (
    <div
      className={[
        "menu-home-layer menu-glass menu-hero-nav-panel",
        visible ? "" : "hidden",
      ].join(" ")}
    >
      {children}
    </div>
  );
}

interface MenuBackBarProps {
  label: string;
  onBack: () => void;
}

export function MenuBackBar({ label, onBack }: MenuBackBarProps) {
  return (
    <button
      type="button"
      onClick={() => {
        playMenuSound("click");
        onBack();
      }}
      className="menu-back-btn group mb-4 flex items-center gap-3 text-left w-full font-ui"
    >
      <span className="text-xl leading-none transition-transform group-hover:-translate-x-1">
        ←
      </span>
      <span className="menu-back-btn__label font-display text-lg uppercase tracking-wide">
        {label}
      </span>
    </button>
  );
}
