import type { FighterColors } from "@/lib/fighterColors";
import { playMenuSound } from "@/audio";
import { useTranslation } from "@/settings/SettingsContext";
import { useEffect, useState } from "react";

interface Props {
  open: boolean;
  colors: FighterColors;
  onApply: (colors: FighterColors) => void;
  onClose: () => void;
}

export function CustomPresetModal({ open, colors, onApply, onClose }: Props) {
  const t = useTranslation();
  const [draft, setDraft] = useState(colors);

  useEffect(() => {
    if (open) setDraft(colors);
  }, [open, colors]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="menu-modal-backdrop pointer-events-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby="custom-preset-title"
      onClick={onClose}
    >
      <div
        className="menu-modal menu-modal--preset"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 id="custom-preset-title" className="menu-modal__title font-display">
          {t.customize.customTitle}
        </h3>
        <p className="menu-modal__hint font-ui">{t.customize.customHint}</p>

        <div className="menu-preset-editor">
          <label className="menu-preset-editor__field">
            <span className="menu-preset-editor__label font-ui">
              {t.customize.body}
            </span>
            <div className="menu-preset-editor__swatch-row">
              <span
                className="menu-preset-editor__preview"
                style={{ background: draft.main }}
              />
              <input
                type="color"
                value={draft.main}
                onChange={(e) =>
                  setDraft((prev) => ({ ...prev, main: e.target.value }))
                }
                className="menu-preset-editor__input"
              />
              <code className="menu-preset-editor__hex font-ui">{draft.main}</code>
            </div>
          </label>

          <label className="menu-preset-editor__field">
            <span className="menu-preset-editor__label font-ui">
              {t.customize.limbTips}
            </span>
            <p className="menu-preset-editor__sublabel font-ui">
              {t.customize.limbTipsHint}
            </p>
            <div className="menu-preset-editor__swatch-row">
              <span
                className="menu-preset-editor__preview"
                style={{ background: draft.secondary }}
              />
              <input
                type="color"
                value={draft.secondary}
                onChange={(e) =>
                  setDraft((prev) => ({ ...prev, secondary: e.target.value }))
                }
                className="menu-preset-editor__input"
              />
              <code className="menu-preset-editor__hex font-ui">
                {draft.secondary}
              </code>
            </div>
          </label>

          <div
            className="menu-preset-editor__sample"
            style={{
              background: `linear-gradient(135deg, ${draft.main} 52%, ${draft.secondary} 52%)`,
            }}
          >
            <span className="menu-preset-editor__sample-label font-ui">
              {t.customize.customPreview}
            </span>
          </div>
        </div>

        <div className="menu-modal__actions">
          <button
            type="button"
            className="menu-nav-btn"
            onClick={() => {
              playMenuSound("click");
              onClose();
            }}
          >
            {t.menu.close}
          </button>
          <button
            type="button"
            className="menu-nav-btn menu-nav-btn--primary"
            onClick={() => {
              playMenuSound("panel");
              onApply(draft);
              onClose();
            }}
          >
            {t.customize.customApply}
          </button>
        </div>
      </div>
    </div>
  );
}
