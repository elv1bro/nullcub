import { useMemo, useState } from "react";
import { ABILITY_META, ITEM_META, type LootRarity } from "@/loadout/catalogMeta";
import { getAbilityDef, isWiredBaseAbility } from "@/loadout/abilities";
import {
  ALL_ABILITY_IDS,
  PASSIVE_ITEM_IDS,
  type AbilityId,
  type PassiveItemId,
} from "@/loadout/types";
import { DEFAULT_ARENA_WEAPON_IDS, WEAPON_CATALOG } from "@/items/defs/catalog";
import { weaponDisplayName } from "@/items/weaponL10n";
import { useSettings, useTranslation } from "@/settings/SettingsContext";
import { playMenuSound } from "@/audio";
import { MAX_HP } from "@/lib/combat";

export type TestArenaPick = {
  playerHp: number;
  opponentHp: number;
  opponentCount: number;
  abilities: AbilityId[];
  items: PassiveItemId[];
  arenaWeaponIds: string[];
};

const MAX_PICK_ABILITIES = 8;
const MAX_PICK_ITEMS = 8;
const MAX_WEAPONS = 4;
const MAX_BOTS = 4;

type ArenaTab = "abilities" | "items" | "weapons";

function rarityClass(r: LootRarity): string {
  return `dev-lab-card__rarity dev-lab-card__rarity--${r}`;
}

function toggleUnique<T extends string>(list: T[], id: T, max: number): T[] {
  if (list.includes(id)) return list.filter((x) => x !== id);
  if (list.length >= max) return list;
  return [...list, id];
}

/**
 * Тестовая арена: набор способностей/предметов, HP, число ботов.
 */
export function TestArenaPanel({
  onStart,
}: {
  onStart: (pick: TestArenaPick) => void;
}) {
  const t = useTranslation();
  const { settings } = useSettings();
  const isRu = settings.language === "ru";
  const [playerHp, setPlayerHp] = useState(MAX_HP);
  const [opponentHp, setOpponentHp] = useState(MAX_HP);
  const [opponentCount, setOpponentCount] = useState(1);
  const [abilities, setAbilities] = useState<AbilityId[]>([
    "dash",
    "flip",
    "brace",
  ]);
  const [items, setItems] = useState<PassiveItemId[]>(["gloves"]);
  const [weapons, setWeapons] = useState<string[]>([
    ...DEFAULT_ARENA_WEAPON_IDS,
  ]);
  const [q, setQ] = useState("");
  const [tab, setTab] = useState<ArenaTab>("abilities");

  const filteredAbilities = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return ALL_ABILITY_IDS.filter((id) => {
      if (!needle) return true;
      return (
        id.includes(needle) ||
        t.loadout.ability[id].toLowerCase().includes(needle) ||
        ABILITY_META[id].cat.includes(needle)
      );
    });
  }, [q, t]);

  const filteredItems = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return PASSIVE_ITEM_IDS.filter((id) => {
      if (!needle) return true;
      return (
        id.includes(needle) ||
        t.loadout.item[id].toLowerCase().includes(needle) ||
        ITEM_META[id].cat.includes(needle)
      );
    });
  }, [q, t]);

  const filteredWeapons = useMemo(() => {
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

  const selectedForTab =
    tab === "abilities"
      ? abilities
      : tab === "items"
        ? items
        : weapons;

  const start = () => {
    playMenuSound("play");
    const arenaWeaponIds =
      weapons.length > 0
        ? weapons.slice(0, MAX_WEAPONS)
        : [...DEFAULT_ARENA_WEAPON_IDS];
    onStart({
      playerHp: Math.max(50, Math.min(5000, Math.round(playerHp))),
      opponentHp: Math.max(50, Math.min(5000, Math.round(opponentHp))),
      opponentCount: Math.max(1, Math.min(MAX_BOTS, opponentCount)),
      abilities: abilities.slice(0, MAX_PICK_ABILITIES),
      items: items.slice(0, MAX_PICK_ITEMS),
      arenaWeaponIds,
    });
  };

  const removeFromTab = (id: string) => {
    if (tab === "abilities") {
      setAbilities((prev) => prev.filter((x) => x !== id));
    } else if (tab === "items") {
      setItems((prev) => prev.filter((x) => x !== id));
    } else {
      setWeapons((prev) => prev.filter((x) => x !== id));
    }
  };

  const chipLabel = (id: string) => {
    if (tab === "abilities") return t.loadout.ability[id as AbilityId];
    if (tab === "items") return t.loadout.item[id as PassiveItemId];
    return weaponDisplayName(id, isRu ? "ru" : "en");
  };

  return (
    <div className="test-arena">
      <div className="test-arena__scroll">
        <header className="test-arena__header">
          <h2 className="dev-lab__title font-display">{t.lab.arenaTitle}</h2>
          <p className="dev-lab__hint font-hand">{t.lab.arenaHint}</p>
        </header>

        <div className="test-arena__params font-ui">
          <label className="test-arena__field">
            <span>{t.lab.arenaPlayerHp}</span>
            <input
              type="number"
              min={50}
              max={5000}
              step={50}
              value={playerHp}
              onChange={(e) => setPlayerHp(Number(e.target.value) || MAX_HP)}
            />
          </label>
          <label className="test-arena__field">
            <span>{t.lab.arenaOpponentHp}</span>
            <input
              type="number"
              min={50}
              max={5000}
              step={50}
              value={opponentHp}
              onChange={(e) => setOpponentHp(Number(e.target.value) || MAX_HP)}
            />
          </label>
          <label className="test-arena__field">
            <span>{t.lab.arenaBotCount}</span>
            <select
              value={opponentCount}
              onChange={(e) => setOpponentCount(Number(e.target.value))}
            >
              {Array.from({ length: MAX_BOTS }, (_, i) => i + 1).map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className="dev-lab__tabs test-arena__tabs" role="tablist">
          {(
            [
              ["abilities", t.lab.tabAbilities, abilities.length, MAX_PICK_ABILITIES],
              ["items", t.lab.tabItems, items.length, MAX_PICK_ITEMS],
              ["weapons", t.lab.tabWeapons, weapons.length, MAX_WEAPONS],
            ] as const
          ).map(([id, label, count, max]) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={tab === id}
              className={
                tab === id ? "dev-lab__tab dev-lab__tab--active" : "dev-lab__tab"
              }
              onClick={() => {
                setTab(id);
                setQ("");
              }}
            >
              {label}{" "}
              <span className="dev-lab__tab-count">
                {count}/{max}
              </span>
            </button>
          ))}
        </div>

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
          {selectedForTab.length === 0 ? (
            <span className="test-arena__chip test-arena__chip--empty">
              {t.lab.pickHint}
            </span>
          ) : (
            selectedForTab.map((id) => (
              <button
                key={id}
                type="button"
                className="test-arena__chip test-arena__chip--on"
                onClick={() => removeFromTab(id)}
                title="remove"
              >
                {chipLabel(id)} ×
              </button>
            ))
          )}
        </div>

        <div className="test-arena__catalog" role="list">
          {tab === "abilities" &&
            filteredAbilities.map((id) => {
              const on = abilities.includes(id);
              const def = getAbilityDef(id);
              const full = !on && abilities.length >= MAX_PICK_ABILITIES;
              return (
                <button
                  key={id}
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
                    setAbilities((prev) =>
                      toggleUnique(prev, id, MAX_PICK_ABILITIES),
                    )
                  }
                >
                  <span className="test-arena-card__check" aria-hidden>
                    {on ? "✓" : "+"}
                  </span>
                  <span className="test-arena-card__body">
                    <span className="test-arena-card__name font-display">
                      {t.loadout.ability[id]}
                    </span>
                    <span className={rarityClass(ABILITY_META[id].rarity)}>
                      {ABILITY_META[id].rarity}
                    </span>
                    <span className="test-arena-card__meta font-ui">
                      {def.kind}
                      {isWiredBaseAbility(id) ? " · ok" : ""}
                    </span>
                  </span>
                </button>
              );
            })}

          {tab === "items" &&
            filteredItems.map((id) => {
              const on = items.includes(id);
              const full = !on && items.length >= MAX_PICK_ITEMS;
              return (
                <button
                  key={id}
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
                    setItems((prev) => toggleUnique(prev, id, MAX_PICK_ITEMS))
                  }
                >
                  <span className="test-arena-card__check" aria-hidden>
                    {on ? "✓" : "+"}
                  </span>
                  <span className="test-arena-card__body">
                    <span className="test-arena-card__name font-display">
                      {t.loadout.item[id]}
                    </span>
                    <span className={rarityClass(ITEM_META[id].rarity)}>
                      {ITEM_META[id].rarity}
                    </span>
                  </span>
                </button>
              );
            })}

          {tab === "weapons" &&
            filteredWeapons.map((w) => {
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
          {abilities.length} abi · {items.length} item · {weapons.length} wep ·{" "}
          {opponentCount} bot
        </p>
        <button
          type="button"
          className="menu-nav-btn menu-nav-btn--primary test-arena__start"
          onClick={start}
          onMouseEnter={() => playMenuSound("hover")}
        >
          {t.lab.arenaStart}
        </button>
      </footer>
    </div>
  );
}
