import type { BlueprintMeta, WorkshopKind } from "@/workshop/blueprintTypes";
import type { LocaleStrings } from "@/i18n/types";

type Props = {
  t: LocaleStrings["workshop"];
  workshopKind: WorkshopKind;
  onKindChange: (kind: WorkshopKind) => void;
  name: string;
  onNameChange: (name: string) => void;
  namePlaceholder: string;
  meta: BlueprintMeta;
  onMetaChange: (patch: Partial<BlueprintMeta>) => void;
  physicsPreview: boolean;
  disabled?: boolean;
};

const KINDS: WorkshopKind[] = ["monster", "item", "arena"];
const KIND_ICON: Record<WorkshopKind, string> = {
  monster: "👾",
  item: "⚔",
  arena: "▤",
};

export function WorkshopParamsPanel({
  t,
  workshopKind,
  onKindChange,
  name,
  onNameChange,
  namePlaceholder,
  meta,
  onMetaChange,
  physicsPreview,
  disabled,
}: Props) {
  const kindLabel = (kind: WorkshopKind) => {
    if (kind === "monster") return t.kindMonster;
    if (kind === "item") return t.kindItem;
    return t.kindArena;
  };

  return (
    <div className="ws-params">
      <div className="ws-kind-tabs">
        {KINDS.map((kind) => (
          <button
            key={kind}
            type="button"
            className={[
              "ws-kind-tab",
              workshopKind === kind ? "ws-kind-tab--active" : "",
            ].join(" ")}
            onClick={() => onKindChange(kind)}
            disabled={disabled || physicsPreview}
            title={kindLabel(kind)}
          >
            <span className="ws-kind-tab__icon">{KIND_ICON[kind]}</span>
            <span className="ws-kind-tab__text">{kindLabel(kind)}</span>
          </button>
        ))}
      </div>

      <input
        className="ws-name-input"
        value={name}
        onChange={(e) => onNameChange(e.target.value.slice(0, 28))}
        placeholder={namePlaceholder}
        disabled={physicsPreview}
      />

      {workshopKind === "monster" && (
        <div className="ws-stats-compact">
          <label className="ws-stat-row">
            <span className="ws-stat-row__icon" style={{ color: "#f87171" }}>
              ♥
            </span>
            <span className="ws-stat-row__label">{t.statHp}</span>
            <input
              type="range"
              className="ws-stat-row__slider"
              min={40}
              max={10000}
              step={20}
              value={meta.maxHp ?? 200}
              onChange={(e) => onMetaChange({ maxHp: Number(e.target.value) })}
            />
            <span className="ws-stat-row__val">{meta.maxHp ?? 200}</span>
          </label>
          <label className="ws-stat-row">
            <span className="ws-stat-row__icon" style={{ color: "#60a5fa" }}>
              🛡
            </span>
            <span className="ws-stat-row__label">{t.statDefense}</span>
            <input
              type="range"
              className="ws-stat-row__slider"
              min={0}
              max={80}
              step={1}
              value={meta.defense ?? 0}
              onChange={(e) => onMetaChange({ defense: Number(e.target.value) })}
            />
            <span className="ws-stat-row__val">{meta.defense ?? 0}%</span>
          </label>
        </div>
      )}

      {workshopKind === "item" && (
        <div className="ws-stats-compact">
          <label className="ws-stat-row">
            <span className="ws-stat-row__label">{t.itemDamageType}</span>
            <select
              className="ws-stat-row__select"
              value={meta.damageType ?? "blunt"}
              onChange={(e) =>
                onMetaChange({
                  damageType: e.target.value as BlueprintMeta["damageType"],
                })
              }
              disabled={physicsPreview}
            >
              <option value="blunt">{t.damageBlunt}</option>
              <option value="pierce">{t.damagePierce}</option>
              <option value="force">{t.damageForce}</option>
              <option value="fire">{t.damageFire}</option>
            </select>
          </label>
          <label className="ws-stat-row">
            <span className="ws-stat-row__label">{t.itemAtk}</span>
            <input
              type="range"
              className="ws-stat-row__slider"
              min={0.5}
              max={3}
              step={0.1}
              value={meta.atkMult ?? 1}
              onChange={(e) => onMetaChange({ atkMult: Number(e.target.value) })}
            />
            <span className="ws-stat-row__val">
              {(meta.atkMult ?? 1).toFixed(1)}×
            </span>
          </label>
        </div>
      )}

      {workshopKind === "arena" && (
        <div className="ws-stats-compact">
          <label className="ws-stat-row">
            <span className="ws-stat-row__label">{t.arenaStatic}</span>
            <input
              type="checkbox"
              checked={meta.static ?? false}
              onChange={(e) => onMetaChange({ static: e.target.checked })}
              disabled={physicsPreview}
            />
          </label>
        </div>
      )}
    </div>
  );
}
