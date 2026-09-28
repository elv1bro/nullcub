import { useTranslation } from "@/settings/SettingsContext";

interface Props {
  embedded?: boolean;
}

/**
 * Экран авторов. Держим его в игре, а не только в README: атрибуция CC0 и OFL
 * должна доезжать до игрока, а не оставаться в репозитории.
 */
export function CreditsPanel({ embedded }: Props) {
  const t = useTranslation();

  const sections: [string, string][] = [
    [t.credits.sectionCode, t.credits.codeOrigin],
    [t.credits.sectionFonts, t.credits.fontsNote],
    [t.credits.sectionAudio, t.credits.audioNote],
    [t.credits.sectionTech, t.credits.techNote],
  ];

  const inner = (
    <div className="menu-credits">
      <p className="menu-credits__intro font-ui">{t.credits.intro}</p>
      {sections.map(([heading, body]) => (
        <section key={heading} className="menu-credits__section">
          <h4 className="menu-credits__heading font-display">{heading}</h4>
          <p className="menu-credits__body font-ui">{body}</p>
        </section>
      ))}
      <p className="menu-credits__rights font-ui">{t.credits.rights}</p>
    </div>
  );

  if (embedded) return <div className="menu-stack">{inner}</div>;

  return (
    <div className="menu-panel-surface menu-panel-pad menu-stack w-full max-w-xs">
      <h3 className="menu-panel-title">{t.credits.title}</h3>
      {inner}
    </div>
  );
}
