import { useMemo, useState } from "react";
import {
  DEFAULT_ARENA_WEAPON_IDS,
  WEAPON_CATALOG,
} from "@/items/defs/catalog";
import { weaponDisplayName } from "@/items/weaponL10n";
import { useSettings, useTranslation } from "@/settings/SettingsContext";
import { playMenuSound } from "@/audio";

export type WeaponSandboxPick = {
  arenaItemIds: string[];
};

const MAX_WEAPONS = 8;

function toggleUnique(list: string[], id: string, max: number): string[] {
  if (list.includes(id)) return list.filter((x) => x !== id);
  if (list.length >= max) return list;
  return [...list, id];
}

/** Песочница: только оружие на арене, без бойцов. */
export function WeaponSandboxPanel({
  onStart,
}: {
  onStart: (pick: WeaponSandboxPick) => void;
}) {
  const t = useTranslation();
  const { settings } = useSettings();
  const isRu = settings.language === "ru";
  const [weapons, setWeapons] = useState<string[]>([
    ...DEFAULT_ARENA_WEAPON_IDS,
  ]);
  const [q, setQ] = useState("");

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return WEAPON_CATALOG.filter((w) => {
      if (!needle) return true;
      const name = weaponDisplayName(w.id, isRu ? "ru" : "en", w.name);
      return (
        w.id.includes(needle) ||
        name.toLowerCase().includes(needle) ||
        w.damageType.includes(needle)
      );
    });
  }, [q, isRu]);

  const start = () => {
    playMenuSound("play");
    onStart({
      arenaItemIds:
        weapons.length > 0
          ? weapons.slice(0, MAX_WEAPONS)
          : [...DEFAULT_ARENA_WEAPON_IDS],
    });
  };

  return (
    <div className="test-arena">
      <div className="test-arena__scroll">
        <header className="test-arena__header">
          <h2 className="dev-lab__title font-display">{t.lab.sandboxTitle}</h2>
          <p className="dev-lab__hint font-hand">{t.lab.sandboxHint}</p>
        </header>

        <label className="dev-lab__search font-ui test-arena__search">
          <span className="sr-only">{t.lab.search}</span>
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t.lab.search}
          />
        </label>

        <div className="test-arena__selected font-ui">
          {weapons.length === 0 ? (
            <span className="test-arena__chip test-arena__chip--empty">
              {t.lab.pickHint}
            </span>
          ) : (
            weapons.map((id) => (
              <button
                key={id}
                type="button"
                className="test-arena__chip test-arena__chip--on"
                onClick={() =>
                  setWeapons((prev) => prev.filter((x) => x !== id))
                }
              >
                {weaponDisplayName(id, isRu ? "ru" : "en")} ×
              </button>
            ))
          )}
        </div>

        <div className="test-arena__catalog" role="list">
          {filtered.map((w) => {
            const on = weapons.includes(w.id);
            const full = !on && weapons.length >= MAX_WEAPONS;
            return (
              <button
                key={w.id}
                type="button"
                role="listitem"
                aria-pressed={on}
                disabled={full}
                className={[
                  "test-arena-card",
                  on ? "test-arena-card--on" : "",
                  full ? "test-arena-card--full" : "",
                ]
                  .filter(Boolean)
                  .join(" ")}
                onClick={() =>
                  setWeapons((prev) => toggleUnique(prev, w.id, MAX_WEAPONS))
                }
              >
                <span className="test-arena-card__check" aria-hidden>
                  {on ? "✓" : "+"}
                </span>
                <span className="test-arena-card__body">
                  <span className="test-arena-card__name font-display">
                    {weaponDisplayName(w.id, isRu ? "ru" : "en", w.name)}
                  </span>
                  <span className="test-arena-card__meta font-ui">
                    {w.damageType} · ×{w.atkMult}
                  </span>
                </span>
              </button>
            );
          })}
        </div>
      </div>

      <footer className="test-arena__footer">
        <p className="test-arena__footer-hint font-ui">
          {weapons.length}/{MAX_WEAPONS} · {t.lab.sandboxDragHint}
        </p>
        <button
          type="button"
          className="menu-nav-btn menu-nav-btn--primary test-arena__start"
          onClick={start}
          onMouseEnter={() => playMenuSound("hover")}
        >
          {t.lab.sandboxStart}
        </button>
      </footer>
    </div>
  );
}
