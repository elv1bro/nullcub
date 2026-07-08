import { blockKindLabel } from "@/workshop/blockLabels";
import type { BlockMeta } from "@/workshop/blockMeta";
import type { WorkshopKind } from "@/workshop/blueprintTypes";
import type { LocaleStrings } from "@/i18n/types";

type Props = {
  t: LocaleStrings["workshop"];
  meta: BlockMeta;
  workshopKind: WorkshopKind;
  radius?: number;
  onRoleChange: (role: "hurtbox" | "armor") => void;
};

export function WorkshopSelectedPart({
  t,
  meta,
  workshopKind,
  radius,
  onRoleChange,
}: Props) {
  return (
    <section className="ws-section ws-section--highlight">
      <header className="ws-section__head">
        <span className="ws-section__icon">◉</span>
        <h2 className="ws-section__title">{t.selectedPart}</h2>
      </header>
      <p className="ws-block-type">{blockKindLabel(meta.blockKind, t, radius)}</p>
      {meta.isHead ? (
        <p className="ws-empty">{t.headAlwaysHurtbox}</p>
      ) : (
        workshopKind === "monster" && (
          <div className="ws-segmented">
            {(["hurtbox", "armor"] as const).map((role) => (
              <button
                key={role}
                type="button"
                className={[
                  "ws-segmented__btn",
                  meta.role === role ? "ws-segmented__btn--active" : "",
                  role === "armor" ? "ws-segmented__btn--armor" : "",
                ].join(" ")}
                onClick={() => onRoleChange(role)}
              >
                {role === "hurtbox" ? t.partRoleHurtbox : t.partRoleArmor}
              </button>
            ))}
          </div>
        )
      )}
    </section>
  );
}
