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
import { GRAB_ENABLED } from "@/lib/battleTuning";
import { isDebugMode } from "@/lib/debugMode";
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

const MOVE_DESC: Record<MoveDir, "descUp" | "descDown" | "descLeft" | "descRight"> =
  {
    up: "descUp",
    down: "descDown",
    left: "descLeft",
    right: "descRight",
  };

const ABILITY_SLOTS: {
  id: AbilitySlot;
  labelKey:
    | "abilityDash"
    | "abilityFlip"
    | "abilityFreeze"
    | "abilityGrabL"
    | "abilityGrabR"
    | "abilityDropWeapon"
    | "abilityLoadoutSlot"
    | "abilityReset";
  descKey:
    | "descDash"
    | "descFlip"
    | "descFreeze"
    | "descGrabL"
    | "descGrabR"
    | "descDropWeapon"
    | "descAbilitySlot"
    | "descReset";
}[] = [
  { id: "dash", labelKey: "abilityDash", descKey: "descDash" },
  { id: "flip", labelKey: "abilityFlip", descKey: "descFlip" },
  { id: "freeze", labelKey: "abilityFreeze", descKey: "descFreeze" },
  ...(GRAB_ENABLED
    ? ([
        { id: "grabL", labelKey: "abilityGrabL", descKey: "descGrabL" },
        { id: "grabR", labelKey: "abilityGrabR", descKey: "descGrabR" },
      ] as const)
    : []),
  {
    id: "dropWeapon",
    labelKey: "abilityDropWeapon",
    descKey: "descDropWeapon",
  },
  {
    id: "slot4",
    labelKey: "abilityLoadoutSlot",
    descKey: "descAbilitySlot",
  },
  { id: "reset", labelKey: "abilityReset", descKey: "descReset" },
];

interface Props {
  embedded?: boolean;
  onClose?: () => void;
}

function BindCell({
  binding,
  listening,
  onListen,
}: {
  binding: string;
  listening: boolean;
  onListen: () => void;
}) {
  const { t } = useSettings();
  return (
    <button
      type="button"
      onClick={onListen}
      className={[
        "menu-key-btn controls-bind-btn",
        listening ? "menu-key-btn--active" : "",
      ].join(" ")}
    >
      {listening ? t.controls.pressKey : formatBindingLabel(binding)}
    </button>
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

  const rows: Array<{
    key: string;
    label: string;
    desc: string;
    p1: { binding: string; kind: "move" | "ability"; id: MoveDir | AbilitySlot };
    p2: {
      binding: string;
      kind: "moveP2" | "abilityP2";
      id: MoveDir | AbilitySlot;
    };
  }> = [
    ...MOVE_DIRS.map((dir) => ({
      key: `move-${dir}`,
      label: t.controls[dir],
      desc: t.controls[MOVE_DESC[dir]],
      p1: {
        binding: settings.controls[dir],
        kind: "move" as const,
        id: dir,
      },
      p2: {
        binding: settings.controlsP2[dir],
        kind: "moveP2" as const,
        id: dir,
      },
    })),
    ...ABILITY_SLOTS.map(({ id, labelKey, descKey }) => ({
      key: `ability-${id}`,
      label: t.battle[labelKey],
      desc: t.controls[descKey],
      p1: {
        binding: settings.abilities[id],
        kind: "ability" as const,
        id,
      },
      p2: {
        binding: settings.abilitiesP2[id],
        kind: "abilityP2" as const,
        id,
      },
    })),
  ];

  const inner = (
    <div className="controls-panel">
      <p className="menu-hint controls-panel__hint">{t.controls.hint}</p>

      <div className="controls-grid" role="table" aria-label={t.controls.title}>
        <div className="controls-grid__head" role="row">
          <span className="controls-grid__action">{t.controls.move}</span>
          <span className="controls-grid__player">{t.controls.player1}</span>
          <span className="controls-grid__player">{t.controls.player2}</span>
        </div>

        {rows.map((row) => (
          <div key={row.key} className="controls-grid__row" role="row">
            <div className="controls-grid__action">
              <span className="controls-grid__label">{row.label}</span>
              <span className="controls-grid__desc">{row.desc}</span>
            </div>
            <BindCell
              binding={row.p1.binding}
              listening={
                listening?.kind === row.p1.kind && listening.id === row.p1.id
              }
              onListen={() =>
                setListening({
                  kind: row.p1.kind,
                  id: row.p1.id as never,
                })
              }
            />
            <BindCell
              binding={row.p2.binding}
              listening={
                listening?.kind === row.p2.kind && listening.id === row.p2.id
              }
              onListen={() =>
                setListening({
                  kind: row.p2.kind,
                  id: row.p2.id as never,
                })
              }
            />
          </div>
        ))}
      </div>

      <p className="menu-hint">
        {t.controls.backKey}: Escape
      </p>

      {isDebugMode() && (
        <button
          type="button"
          className="menu-link-btn"
          onClick={() => openStrikeLab(sendN("STRIKE_LAB"))}
        >
          Strike lab — тест ударов и отталкивания
        </button>
      )}

      <div className="flex gap-2 pt-1">
        <button type="button" className="menu-nav-btn text-sm!" onClick={resetControls}>
          {t.controls.reset}
        </button>
        {!embedded && onClose && (
          <Button type="button" className="text-sm py-1 flex-1" onClick={onClose}>
            {t.controls.close}
          </Button>
        )}
      </div>
    </div>
  );

  if (embedded) return inner;

  return (
    <div className="menu-panel-surface menu-panel-pad menu-stack w-full max-w-lg">
      <h3 className="menu-panel-title">{t.controls.title}</h3>
      {inner}
    </div>
  );
}
