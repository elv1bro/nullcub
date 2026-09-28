import { useMemo, useState, type ReactNode } from "react";
import { ABILITY_DEFS } from "@/loadout/abilities";
import { ABILITY_META, ITEM_META, type LootRarity } from "@/loadout/catalogMeta";
import { ITEM_DEFS } from "@/loadout/items";
import {
  ALL_ABILITY_IDS,
  isBaseAbilityId,
  PASSIVE_ITEM_IDS,
  type AbilityId,
  type FighterLoadout,
  type PassiveItemId,
} from "@/loadout/types";
import { DEFAULT_ARENA_WEAPON_IDS, WEAPON_CATALOG } from "@/items/defs/catalog";
import { weaponDisplayName } from "@/items/weaponL10n";
import { useSettings, useTranslation } from "@/settings/SettingsContext";
import { playMenuSound } from "@/audio";
import {
  TestArenaPanel,
  type TestArenaPick,
} from "@/components/TestArenaPanel";
import {
  WeaponSandboxPanel,
  type WeaponSandboxPick,
} from "@/components/WeaponSandboxPanel";

export type LabFightPick = {
  arenaItemIds: string[];
  loadout: FighterLoadout;
};

function buildLabArenaItems(weaponId: string | null): string[] {
  const primary = weaponId ?? DEFAULT_ARENA_WEAPON_IDS[0] ?? "sword";
  const out = [primary];
  for (const id of DEFAULT_ARENA_WEAPON_IDS) {
    if (out.length >= 4) break;
    if (!out.includes(id)) out.push(id);
  }
  // Если выбранное — не из дефолтов, добиваем копиями выбранного.
  while (out.length < 4) out.push(primary);
  return out;
}

function buildLabLoadout(
  ability: AbilityId | null,
  item: PassiveItemId | null,
): FighterLoadout {
  // Базы (dash/flip/brace) открыты через labUnlockBases; сюда кладём выбранное.
  if (ability && isBaseAbilityId(ability)) {
    return {
      base: ability,
      abilities: [ability, null],
      items: [item, null],
    };
  }
  return {
    base: "dash",
    abilities: [ability, null],
    items: [item, null],
  };
}

type LabTab = "weapons" | "abilities" | "items";

const CAT_LABEL: Record<string, { en: string; ru: string }> = {
  mobility: { en: "Mobility", ru: "Мобильность" },
  offense: { en: "Offense", ru: "Атака" },
  defense: { en: "Defense", ru: "Защита" },
  control: { en: "Control", ru: "Контроль" },
  support: { en: "Support", ru: "Поддержка" },
  chaos: { en: "Chaos", ru: "Хаос" },
  utility: { en: "Utility", ru: "Утилита" },
  set: { en: "Set", ru: "Сет" },
};

function rarityClass(r: LootRarity): string {
  return `dev-lab-card__rarity dev-lab-card__rarity--${r}`;
}

type LabMode = "catalog" | "arena" | "sandbox";

function LabModeTabs({
  mode,
  onMode,
  showArena,
  showSandbox,
}: {
  mode: LabMode;
  onMode: (m: LabMode) => void;
  showArena?: boolean;
  showSandbox?: boolean;
}) {
  const t = useTranslation();
  return (
    <div className="dev-lab__modes" role="tablist" aria-label="lab mode">
      <button
        type="button"
        role="tab"
        aria-selected={mode === "catalog"}
        className={
          mode === "catalog"
            ? "dev-lab__tab dev-lab__tab--active"
            : "dev-lab__tab"
        }
        onClick={() => onMode("catalog")}
      >
        {t.lab.modeCatalog}
      </button>
      {showArena && (
        <button
          type="button"
          role="tab"
          aria-selected={mode === "arena"}
          className={
            mode === "arena"
              ? "dev-lab__tab dev-lab__tab--active"
              : "dev-lab__tab"
          }
          onClick={() => onMode("arena")}
        >
          {t.lab.modeArena}
        </button>
      )}
      {showSandbox && (
        <button
          type="button"
          role="tab"
          aria-selected={mode === "sandbox"}
          className={
            mode === "sandbox"
              ? "dev-lab__tab dev-lab__tab--active"
              : "dev-lab__tab"
          }
          onClick={() => onMode("sandbox")}
        >
          {t.lab.modeSandbox}
        </button>
      )}
    </div>
  );
}

/**
 * Скрытый каталог + тестовая арена + яма с оружием.
 * Открывается через меню «Тесты» после разлока.
 */
export function DevLabPanel({
  onStartFight,
  onStartArena,
  onStartSandbox,
}: {
  onStartFight?: (pick: LabFightPick) => void;
  onStartArena?: (pick: TestArenaPick) => void;
  onStartSandbox?: (pick: WeaponSandboxPick) => void;
}) {
  const [mode, setMode] = useState<LabMode>("catalog");
  const showModes = Boolean(onStartArena || onStartSandbox);

  if (mode === "arena" && onStartArena) {
    return (
      <div className="dev-lab-hub">
        <LabModeTabs
          mode={mode}
          onMode={setMode}
          showArena={Boolean(onStartArena)}
          showSandbox={Boolean(onStartSandbox)}
        />
        <TestArenaPanel onStart={onStartArena} />
      </div>
    );
  }

  if (mode === "sandbox" && onStartSandbox) {
    return (
      <div className="dev-lab-hub">
        <LabModeTabs
          mode={mode}
          onMode={setMode}
          showArena={Boolean(onStartArena)}
          showSandbox={Boolean(onStartSandbox)}
        />
        <WeaponSandboxPanel onStart={onStartSandbox} />
      </div>
    );
  }

  return (
    <LabCatalogPanel
      onStartFight={onStartFight}
      modeTabs={
        showModes ? (
          <LabModeTabs
            mode="catalog"
            onMode={setMode}
            showArena={Boolean(onStartArena)}
            showSandbox={Boolean(onStartSandbox)}
          />
        ) : null
      }
    />
  );
}

function LabCatalogPanel({
  onStartFight,
  modeTabs,
}: {
  onStartFight?: (pick: LabFightPick) => void;
  modeTabs: ReactNode;
}) {
  const t = useTranslation();
  const { settings } = useSettings();
  const isRu = settings.language === "ru";
  const [tab, setTab] = useState<LabTab>("weapons");
  const [q, setQ] = useState("");
  const [selectedWeapon, setSelectedWeapon] = useState<string | null>(
    WEAPON_CATALOG[0]?.id ?? null,
  );
  const [selectedAbility, setSelectedAbility] = useState<AbilityId | null>(
    "dash",
  );
  const [selectedItem, setSelectedItem] = useState<PassiveItemId | null>(
    "gloves",
  );

  const cat = (id: string) => {
    const row = CAT_LABEL[id];
    if (!row) return id;
    return isRu ? row.ru : row.en;
  };

  const weapons = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return WEAPON_CATALOG.filter((w) => {
      if (!needle) return true;
      const localName = weaponDisplayName(w.id, isRu ? "ru" : "en", w.name);
      return (
        w.id.includes(needle) ||
        w.name.toLowerCase().includes(needle) ||
        localName.toLowerCase().includes(needle) ||
        w.damageType.includes(needle)
      );
    });
  }, [q, isRu]);

  const abilities = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return ALL_ABILITY_IDS.filter((id) => {
      if (!needle) return true;
      const name = t.loadout.ability[id];
      const desc = t.loadout.abilityDesc[id];
      return (
        id.toLowerCase().includes(needle) ||
        name.toLowerCase().includes(needle) ||
        desc.toLowerCase().includes(needle) ||
        ABILITY_META[id].cat.includes(needle)
      );
    });
  }, [q, t]);

  const items = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return PASSIVE_ITEM_IDS.filter((id) => {
      if (!needle) return true;
      const name = t.loadout.item[id];
      const desc = t.loadout.itemDesc[id];
      return (
        id.toLowerCase().includes(needle) ||
        name.toLowerCase().includes(needle) ||
        desc.toLowerCase().includes(needle) ||
        ITEM_META[id].cat.includes(needle)
      );
    });
  }, [q, t]);

  const detailWeapon = selectedWeapon
    ? WEAPON_CATALOG.find((w) => w.id === selectedWeapon)
    : null;
  const detailAbility = selectedAbility ? ABILITY_DEFS[selectedAbility] : null;
  const detailItem = selectedItem ? ITEM_DEFS[selectedItem] : null;

  const weaponLabel = selectedWeapon
    ? weaponDisplayName(
        selectedWeapon,
        isRu ? "ru" : "en",
        detailWeapon?.name,
      )
    : "—";
  const abilityLabel = selectedAbility
    ? t.loadout.ability[selectedAbility]
    : "—";
  const itemLabel = selectedItem ? t.loadout.item[selectedItem] : "—";

  const startFight = () => {
    if (!onStartFight) return;
    playMenuSound("play");
    onStartFight({
      arenaItemIds: buildLabArenaItems(selectedWeapon),
      loadout: buildLabLoadout(selectedAbility, selectedItem),
    });
  };

  return (
    <div className="dev-lab">
      {modeTabs}
      <header className="dev-lab__header">
        <h2 className="dev-lab__title font-display">{t.lab.title}</h2>
        <p className="dev-lab__hint font-hand">{t.lab.hint}</p>
      </header>

      <div className="dev-lab__tabs" role="tablist">
        {(
          [
            ["weapons", t.lab.tabWeapons, weapons.length],
            ["abilities", t.lab.tabAbilities, abilities.length],
            ["items", t.lab.tabItems, items.length],
          ] as const
        ).map(([id, label, count]) => (
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
            <span className="dev-lab__tab-count">{count}</span>
          </button>
        ))}
      </div>

      <label className="dev-lab__search font-ui">
        <span className="sr-only">{t.lab.search}</span>
        <input
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t.lab.search}
        />
      </label>

      <div className="dev-lab__body">
        <div className="dev-lab__list" role="list">
          {tab === "weapons" &&
            weapons.map((w) => (
              <button
                key={w.id}
                type="button"
                role="listitem"
                className={
                  selectedWeapon === w.id
                    ? "dev-lab-card dev-lab-card--active"
                    : "dev-lab-card"
                }
                onClick={() => setSelectedWeapon(w.id)}
              >
                <span className="dev-lab-card__name font-display">
                  {weaponDisplayName(w.id, isRu ? "ru" : "en", w.name)}
                </span>
                <span className="dev-lab-card__meta font-ui">
                  {w.damageType} · ×{w.atkMult}
                </span>
                <code className="dev-lab-card__id font-ui">{w.id}</code>
              </button>
            ))}

          {tab === "abilities" &&
            abilities.map((id) => {
              const meta = ABILITY_META[id];
              const def = ABILITY_DEFS[id];
              return (
                <button
                  key={id}
                  type="button"
                  role="listitem"
                  className={
                    selectedAbility === id
                      ? "dev-lab-card dev-lab-card--active"
                      : "dev-lab-card"
                  }
                  onClick={() => setSelectedAbility(id)}
                >
                  <span className="dev-lab-card__name font-display">
                    {t.loadout.ability[id]}
                  </span>
                  <span className={rarityClass(meta.rarity)}>{meta.rarity}</span>
                  <span className="dev-lab-card__meta font-ui">
                    {def.kind} · {cat(meta.cat)}
                  </span>
                  <code className="dev-lab-card__id font-ui">{id}</code>
                </button>
              );
            })}

          {tab === "items" &&
            items.map((id) => {
              const meta = ITEM_META[id];
              return (
                <button
                  key={id}
                  type="button"
                  role="listitem"
                  className={
                    selectedItem === id
                      ? "dev-lab-card dev-lab-card--active"
                      : "dev-lab-card"
                  }
                  onClick={() => setSelectedItem(id)}
                >
                  <span className="dev-lab-card__name font-display">
                    {t.loadout.item[id]}
                  </span>
                  <span className={rarityClass(meta.rarity)}>{meta.rarity}</span>
                  <span className="dev-lab-card__meta font-ui">
                    {cat(meta.cat)}
                  </span>
                  <code className="dev-lab-card__id font-ui">{id}</code>
                </button>
              );
            })}
        </div>

        <aside className="dev-lab__detail">
          {tab === "weapons" && detailWeapon && (
            <>
              <h3 className="dev-lab__detail-title font-display">
                {weaponDisplayName(
                  detailWeapon.id,
                  isRu ? "ru" : "en",
                  detailWeapon.name,
                )}
              </h3>
              <p className="dev-lab__detail-desc font-ui">
                {t.lab.weaponBlurb
                  .replace("{type}", detailWeapon.damageType)
                  .replace("{atk}", String(detailWeapon.atkMult))
                  .replace("{drop}", String(detailWeapon.dropChanceMult))}
              </p>
              <dl className="dev-lab__stats font-ui">
                <div>
                  <dt>id</dt>
                  <dd>
                    <code>{detailWeapon.id}</code>
                  </dd>
                </div>
                <div>
                  <dt>{t.lab.statDamage}</dt>
                  <dd>{detailWeapon.damageType}</dd>
                </div>
                <div>
                  <dt>{t.lab.statAtk}</dt>
                  <dd>×{detailWeapon.atkMult}</dd>
                </div>
                <div>
                  <dt>{t.lab.statDrop}</dt>
                  <dd>×{detailWeapon.dropChanceMult}</dd>
                </div>
                <div>
                  <dt>{t.lab.statParts}</dt>
                  <dd>
                    {detailWeapon.bodies.length} bodies /{" "}
                    {detailWeapon.links.length} links
                  </dd>
                </div>
              </dl>
            </>
          )}

          {tab === "abilities" && detailAbility && selectedAbility && (
            <>
              <h3 className="dev-lab__detail-title font-display">
                {t.loadout.ability[selectedAbility]}
              </h3>
              <p className="dev-lab__detail-desc font-ui">
                {t.loadout.abilityDesc[selectedAbility]}
              </p>
              <dl className="dev-lab__stats font-ui">
                <div>
                  <dt>id</dt>
                  <dd>
                    <code>{selectedAbility}</code>
                  </dd>
                </div>
                <div>
                  <dt>{t.lab.statKind}</dt>
                  <dd>{detailAbility.kind}</dd>
                </div>
                <div>
                  <dt>{t.lab.statCat}</dt>
                  <dd>{cat(ABILITY_META[selectedAbility].cat)}</dd>
                </div>
                <div>
                  <dt>{t.lab.statRarity}</dt>
                  <dd>{ABILITY_META[selectedAbility].rarity}</dd>
                </div>
                {detailAbility.cooldownMs != null && (
                  <div>
                    <dt>{t.lab.statCd}</dt>
                    <dd>{(detailAbility.cooldownMs / 1000).toFixed(1)}s</dd>
                  </div>
                )}
                {detailAbility.durationMs != null && (
                  <div>
                    <dt>{t.lab.statDur}</dt>
                    <dd>{(detailAbility.durationMs / 1000).toFixed(1)}s</dd>
                  </div>
                )}
              </dl>
            </>
          )}

          {tab === "items" && detailItem && selectedItem && (
            <>
              <h3 className="dev-lab__detail-title font-display">
                {t.loadout.item[selectedItem]}
              </h3>
              <p className="dev-lab__detail-desc font-ui">
                {t.loadout.itemDesc[selectedItem]}
              </p>
              <dl className="dev-lab__stats font-ui">
                <div>
                  <dt>id</dt>
                  <dd>
                    <code>{selectedItem}</code>
                  </dd>
                </div>
                <div>
                  <dt>{t.lab.statCat}</dt>
                  <dd>{cat(ITEM_META[selectedItem].cat)}</dd>
                </div>
                <div>
                  <dt>{t.lab.statRarity}</dt>
                  <dd>{ITEM_META[selectedItem].rarity}</dd>
                </div>
                {detailItem.atkMult != null && (
                  <div>
                    <dt>{t.lab.statAtk}</dt>
                    <dd>×{detailItem.atkMult}</dd>
                  </div>
                )}
                {detailItem.defMult != null && (
                  <div>
                    <dt>{t.lab.statDef}</dt>
                    <dd>×{detailItem.defMult}</dd>
                  </div>
                )}
                {detailItem.moveMult != null && (
                  <div>
                    <dt>{t.lab.statMove}</dt>
                    <dd>×{detailItem.moveMult}</dd>
                  </div>
                )}
                {detailItem.critChance != null && (
                  <div>
                    <dt>{t.lab.statCrit}</dt>
                    <dd>{Math.round(detailItem.critChance * 100)}%</dd>
                  </div>
                )}
                {detailItem.knockbackOutMult != null && (
                  <div>
                    <dt>{t.lab.statKb}</dt>
                    <dd>×{detailItem.knockbackOutMult}</dd>
                  </div>
                )}
              </dl>
            </>
          )}

          {((tab === "weapons" && !detailWeapon) ||
            (tab === "abilities" && !detailAbility) ||
            (tab === "items" && !detailItem)) && (
            <p className="dev-lab__empty font-ui">{t.lab.pickHint}</p>
          )}
        </aside>
      </div>

      <footer className="dev-lab__footer">
        <p className="dev-lab__summary font-ui">
          {t.lab.loadoutSummary
            .replace("{weapon}", weaponLabel)
            .replace("{ability}", abilityLabel)
            .replace("{item}", itemLabel)}
          <br />
          <span className="opacity-80">{t.lab.castHint}</span>
        </p>
        {onStartFight && (
          <button
            type="button"
            className="menu-nav-btn menu-nav-btn--primary dev-lab__start"
            onClick={startFight}
            onMouseEnter={() => playMenuSound("hover")}
          >
            {t.lab.startFight}
          </button>
        )}
      </footer>
    </div>
  );
}
