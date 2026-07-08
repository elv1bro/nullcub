import { Button } from "@/components/Button";
import { GameContext } from "@/GameContext";
import {
  bindingFromKeyboardEvent,
  formatBindingLabel,
} from "@/input/keyBindings";
import {
  useSettings,
  type AbilityBindings,
  type ControlBindings,
} from "@/settings/SettingsContext";
import { openStrikeLab } from "@/lib/strikeLabMode";
import { useContext, useEffect, useState } from "react";

type MoveDir = keyof ControlBindings;
type AbilitySlot = keyof AbilityBindings;

type ListeningTarget =
  | { kind: "move"; id: MoveDir }
  | { kind: "moveP2"; id: MoveDir }
  | { kind: "ability"; id: AbilitySlot }
  | { kind: "abilityP2"; id: AbilitySlot }
  | null;

const MOVE_DIRS: MoveDir[] = ["up", "down", "left", "right"];

const ABILITY_SLOTS: {
  id: AbilitySlot;
  labelKey:
    | "abilityDash"
    | "abilityFlip"
    | "abilityFreeze"
    | "abilityGrabL"
    | "abilityGrabR"
    | "abilitySlotEmpty"
    | "abilityReset";
  disabled?: boolean;
}[] = [
  { id: "dash", labelKey: "abilityDash" },
  { id: "flip", labelKey: "abilityFlip" },
  { id: "freeze", labelKey: "abilityFreeze" },
  { id: "grabL", labelKey: "abilityGrabL" },
  { id: "grabR", labelKey: "abilityGrabR" },
  { id: "slot4", labelKey: "abilitySlotEmpty", disabled: true },
  { id: "reset", labelKey: "abilityReset" },
];

interface Props {
  embedded?: boolean;
  onClose?: () => void;
}

function KeyBindButton({
  label,
  binding,
  listening,
  onListen,
  disabled,
}: {
  label: string;
  binding: string;
  listening: boolean;
  onListen: () => void;
  disabled?: boolean;
}) {
  const { t } = useSettings();

  return (
    <li className="flex items-center justify-between gap-2">
      <span className="menu-label mb-0!">{label}</span>
      <button
        type="button"
        onClick={onListen}
        disabled={disabled}
        className={[
          "menu-key-btn",
          listening ? "menu-key-btn--active" : "",
          disabled ? "opacity-45 cursor-not-allowed" : "",
        ].join(" ")}
      >
        {listening ? t.controls.pressKey : formatBindingLabel(binding)}
      </button>
    </li>
  );
}

export function ControlsPanel({ embedded, onClose }: Props) {
  const { sendN } = useContext(GameContext);
  const {
    t,
    settings,
    setControl,
    setControlP2,
    setAbility,
    setAbilityP2,
    resetControls,
  } = useSettings();
  const [listening, setListening] = useState<ListeningTarget>(null);

  useEffect(() => {
    if (!listening) return;

    const onKey = (e: KeyboardEvent) => {
      e.preventDefault();
      if (e.code === "Escape") {
        setListening(null);
        return;
      }
      const code = bindingFromKeyboardEvent(e);
      if (listening.kind === "move") {
        setControl(listening.id, code);
      } else if (listening.kind === "moveP2") {
        setControlP2(listening.id, code);
      } else if (listening.kind === "ability") {
        setAbility(listening.id, code);
      } else {
        setAbilityP2(listening.id, code);
      }
      setListening(null);
    };

    window.addEventListener("keydown", onKey, { capture: true });
    return () => window.removeEventListener("keydown", onKey, { capture: true });
  }, [listening, setControl, setControlP2, setAbility, setAbilityP2]);

  const renderMoveSection = (
    title: string,
    hint: string,
    bindings: ControlBindings,
    kind: "move" | "moveP2",
  ) => (
    <>
      <p className="menu-hint">{title}</p>
      <p className="menu-hint text-xs! -mt-1">{hint}</p>
      <ul className="space-y-2">
        {MOVE_DIRS.map((dir) => (
          <KeyBindButton
            key={`${kind}-${dir}`}
            label={t.controls[dir]}
            binding={bindings[dir]}
            listening={listening?.kind === kind && listening.id === dir}
            onListen={() => setListening({ kind, id: dir })}
          />
        ))}
      </ul>
    </>
  );

  const renderAbilitySection = (
    title: string,
    bindings: AbilityBindings,
    kind: "ability" | "abilityP2",
  ) => (
    <>
      <p className="menu-hint pt-2">{title}</p>
      <ul className="space-y-2">
        {ABILITY_SLOTS.map(({ id, labelKey, disabled }) => (
          <KeyBindButton
            key={`${kind}-${id}`}
            label={t.battle[labelKey]}
            binding={bindings[id]}
            listening={listening?.kind === kind && listening.id === id}
            onListen={() => setListening({ kind, id })}
            disabled={disabled}
          />
        ))}
      </ul>
    </>
  );

  const inner = (
    <>
      {renderMoveSection(t.controls.move, t.controls.arrowsHint, settings.controls, "move")}
      {renderAbilitySection(t.controls.abilities, settings.abilities, "ability")}

      {renderMoveSection(
        t.controls.moveP2,
        t.controls.moveP2Hint,
        settings.controlsP2,
        "moveP2",
      )}
      {renderAbilitySection(t.controls.abilitiesP2, settings.abilitiesP2, "abilityP2")}

      <p className="menu-hint">{t.controls.backKey}: Escape</p>

      <button
        type="button"
        className="menu-link-btn"
        onClick={() => openStrikeLab(sendN("STRIKE_LAB"))}
      >
        Strike lab — тест ударов и отталкивания
      </button>

      <div className="flex gap-2 pt-2">
        <button type="button" className="menu-nav-btn text-sm!" onClick={resetControls}>
          {t.controls.reset}
        </button>
        {!embedded && onClose && (
          <Button type="button" className="text-sm py-1 flex-1" onClick={onClose}>
            {t.controls.close}
          </Button>
        )}
      </div>
    </>
  );

  if (embedded) return <div className="menu-stack">{inner}</div>;

  return (
    <div className="menu-panel-surface menu-panel-pad menu-stack w-full max-w-xs">
      <h3 className="menu-panel-title">{t.controls.title}</h3>
      {inner}
    </div>
  );
}
