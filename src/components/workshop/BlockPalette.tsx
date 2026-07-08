import type { BlockTemplate } from "@/workshop/blockCatalog";
import type { LocaleStrings } from "@/i18n/types";

type Props = {
  templates: BlockTemplate[];
  disabled?: boolean;
  dragging?: boolean;
  t: LocaleStrings["workshop"];
  onDragStart: (template: BlockTemplate) => void;
};

export function BlockPalette({
  templates,
  disabled,
  dragging,
  t,
  onDragStart,
}: Props) {
  return (
    <div className="ws-palette-panel">
      <p className="ws-palette-panel__lead">{t.paletteLead}</p>
      {dragging && (
        <p className="ws-palette-panel__drop">{t.paletteDropActive}</p>
      )}
      <div className="ws-palette">
        {templates.map((template) => (
          <button
            key={template.id}
            type="button"
            className="ws-palette__item"
            disabled={disabled}
            title={t[template.descKey]}
            onMouseDown={(e) => {
              e.preventDefault();
              onDragStart(template);
            }}
          >
            <span
              className="ws-palette__swatch"
              style={{
                width: `${Math.min(40, template.radius * 1.8)}px`,
                height: `${Math.min(40, template.radius * 1.8)}px`,
                borderColor: template.accent,
                boxShadow: `0 0 14px ${template.accent}55`,
              }}
            >
              <span className="ws-palette__icon">{template.icon}</span>
            </span>
            <span className="ws-palette__label">{t[template.labelKey]}</span>
          </button>
        ))}
      </div>
      <p className="ws-palette-panel__foot">{t.paletteFoot}</p>
    </div>
  );
}
