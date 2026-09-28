import { useSettings } from "@/settings/SettingsContext";
import { formatKeyLabel } from "@/input/PlayerMovementInput";

export const BATTLE_ONBOARD_KEY = "ragdoll-battle-onboarded";

export function hasSeenBattleOnboarding(): boolean {
  try {
    return localStorage.getItem(BATTLE_ONBOARD_KEY) === "1";
  } catch {
    return true;
  }
}

export function markBattleOnboardingSeen(): void {
  try {
    localStorage.setItem(BATTLE_ONBOARD_KEY, "1");
  } catch {
    /* ignore */
  }
}

type Props = {
  onDismiss: () => void;
};

/** Первый бой: одно короткое окно — лети головой + рывок. */
export function BattleOnboarding({ onDismiss }: Props) {
  const { t, settings } = useSettings();
  const c = settings.controls;
  const move = `${formatKeyLabel(c.up)}${formatKeyLabel(c.left)}${formatKeyLabel(c.down)}${formatKeyLabel(c.right)}`;
  const dash = formatKeyLabel(settings.abilities.dash);

  return (
    <div className="battle-onboard" role="dialog" aria-modal="true">
      <div className="battle-onboard__card">
        <h2 className="battle-onboard__title">{t.battle.onboardTitle}</h2>
        <ol className="battle-onboard__steps">
          <li>
            {t.battle.onboardStepMove} <strong>{move}</strong>
          </li>
          <li>
            {t.battle.onboardStepDash} <strong>{dash}</strong>
          </li>
          <li>{t.battle.onboardStepHit}</li>
        </ol>
        <button
          type="button"
          className="battle-onboard__go"
          onClick={onDismiss}
        >
          {t.battle.onboardGo}
        </button>
      </div>
    </div>
  );
}
