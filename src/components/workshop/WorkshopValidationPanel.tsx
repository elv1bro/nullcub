import type { LocaleStrings } from "@/i18n/types";
import type { WorkshopValidationView } from "@/workshop/useWorkshopValidation";

type Props = {
  t: LocaleStrings["workshop"];
  validation: WorkshopValidationView;
  kind: "monster" | "item" | "arena";
  stressOk?: boolean;
};

export function WorkshopValidationPanel({
  t,
  validation,
  kind,
  stressOk = true,
}: Props) {
  if (kind !== "monster") return null;

  const { ready, hasHead, hasHurtbox, hasLinks, orphans, check } = validation;
  const allReady = ready && stressOk;
  const reasonMsg =
    !check.ok && check.reason in t
      ? t[check.reason as keyof typeof t]
      : null;

  return (
    <div
      className={[
        "ws-validation",
        allReady ? "ws-validation--ready" : "ws-validation--blocked",
      ].join(" ")}
    >
      <div className="ws-validation__title">
        {allReady ? t.readyToFight : t.notReadyToFight}
      </div>
      <ul className="ws-validation__list">
        <li className={hasHead ? "ok" : "bad"}>
          {hasHead ? "✓" : "✗"} {t.checkHead}
        </li>
        <li className={hasHurtbox ? "ok" : "bad"}>
          {hasHurtbox ? "✓" : "✗"} {t.checkHurtbox}
        </li>
        <li className={hasLinks ? "ok" : "bad"}>
          {hasLinks ? "✓" : "✗"} {t.checkLinks}
        </li>
        <li className={orphans.length === 0 ? "ok" : "bad"}>
          {orphans.length === 0 ? "✓" : "✗"}{" "}
          {orphans.length === 0
            ? t.checkConnected
            : t.orphanParts(orphans.length)}
        </li>
        <li className={stressOk ? "ok" : "bad"}>
          {stressOk ? "✓" : "✗"} {t.checkStress}
        </li>
      </ul>
      {!allReady && typeof reasonMsg === "string" && (
        <p className="ws-validation__hint">{reasonMsg}</p>
      )}
      {!stressOk && (
        <p className="ws-validation__hint">{t.stressBlocked}</p>
      )}
    </div>
  );
}
