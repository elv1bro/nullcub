import { useEffect, useRef } from "react";
import { useTranslation } from "@/settings/SettingsContext";
import {
  ABILITY_DEFS,
  isAbilityId,
  isPassiveItemId,
  type DraftCardId,
} from "@/loadout";

export interface LootTooltipProps {
  card: DraftCardId;
  /** Экранные координаты якоря (клик). */
  x: number;
  y: number;
  onClose: () => void;
}

/** Тултип в духе Dota: клик по карте → имя + описание, клик снаружи закрывает. */
export function LootTooltip({ card, x, y, onClose }: LootTooltipProps) {
  const t = useTranslation();
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("mousedown", onDown);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("mousedown", onDown);
    };
  }, [onClose]);

  const kind = isPassiveItemId(card)
    ? t.loadout.kindItem
    : isAbilityId(card)
      ? ABILITY_DEFS[card].kind
      : "card";
  const name = isPassiveItemId(card)
    ? t.loadout.item[card]
    : t.loadout.ability[card];
  const desc = isPassiveItemId(card)
    ? t.loadout.itemDesc[card]
    : t.loadout.abilityDesc[card];

  const left = Math.min(window.innerWidth - 280, Math.max(12, x + 12));
  const top = Math.min(window.innerHeight - 160, Math.max(12, y + 12));

  return (
    <div
      ref={ref}
      className="loot-tooltip"
      style={{ left, top }}
      role="tooltip"
    >
      <div className="loot-tooltip__kind font-ui">{kind}</div>
      <div className="loot-tooltip__name font-display">{name}</div>
      <p className="loot-tooltip__desc font-ui">{desc}</p>
    </div>
  );
}
