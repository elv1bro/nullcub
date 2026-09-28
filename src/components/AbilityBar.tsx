import type { AbilityBindings } from "@/settings/SettingsContext";
import type { AbilityCooldownView } from "@/lib/usePlayerAbilities";
import { formatBindingLabel } from "@/input/keyBindings";
import type { ReactNode } from "react";
import {
  DASH_COOLDOWN_MS,
  FLIP_COOLDOWN_MS,
  BRACE_COOLDOWN_MS,
  RESET_COOLDOWN_MS,
  GRAB_ENABLED,
} from "@/lib/battleTuning";
import { getBattleConfig } from "@/lib/battleConfig";
import { useSettings } from "@/settings/SettingsContext";
import {
  BraceIcon,
  DashIcon,
  FlipIcon,
  ResetIcon,
} from "@/components/abilityIcons";
import type { AbilityId, PassiveItemId } from "@/loadout/types";

type Props = AbilityCooldownView & {
  disabled?: boolean;
  bindings?: AbilityBindings;
};

function AbilitySlot({
  label,
  keyLabel,
  ready,
  active,
  disabled: slotDisabled,
  remainingMs,
  totalMs,
  flashAt,
  activeColor = "cyan",
  children,
}: {
  label: string;
  keyLabel: string;
  ready: boolean;
  active?: boolean;
  disabled?: boolean;
  remainingMs: number;
  totalMs: number;
  flashAt: number;
  activeColor?: "cyan" | "amber" | "violet" | "sky";
  children: ReactNode;
}) {
  const progress = totalMs > 0 ? remainingMs / totalMs : 0;
  const seconds = (remainingMs / 1000).toFixed(1);
  const flashed = performance.now() - flashAt < 180;

  const readyStyles = {
    cyan: "border-cyan-400/70 bg-cyan-950/50 text-cyan-200 shadow-[0_0_12px_rgba(34,211,238,0.35)]",
    amber:
      "border-amber-400/80 bg-amber-950/50 text-amber-200 shadow-[0_0_14px_rgba(251,191,36,0.45)]",
    violet:
      "border-violet-400/70 bg-violet-950/50 text-violet-200 shadow-[0_0_12px_rgba(167,139,250,0.35)]",
    sky: "border-sky-400/70 bg-sky-950/50 text-sky-200 shadow-[0_0_12px_rgba(56,189,248,0.35)]",
  } as const;

  const dotStyles = {
    cyan: "bg-cyan-400 shadow-[0_0_6px_cyan]",
    amber: "bg-amber-400 shadow-[0_0_6px_#fbbf24]",
    violet: "bg-violet-400 shadow-[0_0_6px_#a78bfa]",
    sky: "bg-sky-400 shadow-[0_0_6px_#38bdf8]",
  } as const;

  const color = active ? "amber" : activeColor;
  const enabled = !slotDisabled;

  return (
    <div
      className={[
        "ability-slot relative flex flex-col items-center gap-1 select-none",
        enabled && (ready || active) ? "opacity-100" : "opacity-55",
        slotDisabled ? "ability-slot--empty" : "",
      ].join(" ")}
      title={label}
    >
      <div
        className={[
          "ability-slot__icon relative w-14 h-14 rounded-xl border-2 flex items-center justify-center overflow-hidden transition-colors duration-150",
          slotDisabled
            ? "border-dashed border-gray-700/80 bg-black/35 text-gray-600"
            : ready || active
              ? readyStyles[color]
              : "border-gray-600/80 bg-black/55 text-gray-500",
          flashed && enabled && (ready || active) ? "scale-110 border-white/90" : "",
        ].join(" ")}
      >
        {children}
        {enabled && !ready && !active && (
          <>
            <div
              className="absolute inset-0 bg-black/65 pointer-events-none"
              style={{
                clipPath: `polygon(0 ${(1 - progress) * 100}%, 100% ${(1 - progress) * 100}%, 100% 100%, 0 100%)`,
              }}
            />
            <span className="absolute inset-0 flex items-center justify-center text-sm font-black tabular-nums text-white drop-shadow ability-slot__cd">
              {seconds}
            </span>
          </>
        )}
        {enabled && (ready || active) && (
          <span
            className={`absolute top-0.5 right-0.5 w-2 h-2 rounded-full ${dotStyles[color]}`}
          />
        )}
      </div>
      <span className="ability-slot__key text-[10px] font-ui uppercase tracking-wider text-gray-400">
        {keyLabel}
      </span>
      <span className="ability-slot__label text-[10px] font-ui text-gray-500 max-w-16 text-center leading-tight">
        {label}
      </span>
    </div>
  );
}

export function AbilityBar({
  dashRemainingMs,
  dashActiveRemainingMs,
  flipRemainingMs,
  freezeRemainingMs,
  freezeActiveRemainingMs,
  resetRemainingMs,
  dashReady,
  flipReady,
  freezeReady,
  resetReady,
  lastDashFlash,
  lastFlipFlash,
  lastFreezeFlash,
  lastResetFlash,
  disabled,
  bindings,
}: Props) {
  const { t, settings } = useSettings();
  const abilities = bindings ?? settings.abilities;
  const battle = getBattleConfig();
  const loadout =
    battle.kind === "lab" || battle.kind === "testArena"
      ? battle.loadout
      : battle.kind === "roguelike"
        ? battle.loadouts.you ??
          battle.loadouts.player ??
          Object.values(battle.loadouts)[0]
        : undefined;
  const castList =
    battle.kind === "testArena" ? battle.castAbilities : undefined;
  const slotAbility = (castList?.[0] ??
    loadout?.abilities[0] ??
    null) as AbilityId | null;
  const slotItem = (loadout?.items[0] ??
    (battle.kind === "testArena" ? battle.extraItems[0] : null) ??
    null) as PassiveItemId | null;
  const castCount = castList?.length ?? (slotAbility ? 1 : 0);
  const itemCount =
    battle.kind === "testArena" && loadout
      ? loadout.items.filter(Boolean).length + battle.extraItems.length
      : slotItem
        ? 1
        : 0;

  if (disabled) return null;

  const dashActive = dashActiveRemainingMs > 0;
  const freezeActive = freezeActiveRemainingMs > 0;

  return (
    <div className="ability-bar flex items-end justify-center gap-3 pointer-events-none">
      <AbilitySlot
        label={t.battle.abilityDash}
        keyLabel={formatBindingLabel(abilities.dash)}
        ready={dashReady}
        active={dashActive}
        remainingMs={dashRemainingMs}
        totalMs={DASH_COOLDOWN_MS}
        flashAt={lastDashFlash}
        activeColor="cyan"
      >
        <DashIcon className="ability-icon ability-icon--bar" />
      </AbilitySlot>
      <AbilitySlot
        label={t.battle.abilityFlip}
        keyLabel={formatBindingLabel(abilities.flip)}
        ready={flipReady}
        remainingMs={flipRemainingMs}
        totalMs={FLIP_COOLDOWN_MS}
        flashAt={lastFlipFlash}
        activeColor="violet"
      >
        <FlipIcon className="ability-icon ability-icon--bar" />
      </AbilitySlot>
      <AbilitySlot
        label={t.battle.abilityFreeze}
        keyLabel={formatBindingLabel(abilities.freeze)}
        ready={freezeReady}
        active={freezeActive}
        remainingMs={freezeRemainingMs}
        totalMs={BRACE_COOLDOWN_MS}
        flashAt={lastFreezeFlash}
        activeColor="sky"
      >
        <BraceIcon className="ability-icon ability-icon--bar" />
      </AbilitySlot>
      {GRAB_ENABLED && (
        <>
      <AbilitySlot
        label={t.battle.abilityGrabL}
        keyLabel={formatBindingLabel(abilities.grabL)}
        ready={true}
        active={false}
        remainingMs={0}
        totalMs={0}
        flashAt={0}
        activeColor="amber"
      >
        <span className="text-lg font-black">L</span>
      </AbilitySlot>
      <AbilitySlot
        label={t.battle.abilityGrabR}
        keyLabel={formatBindingLabel(abilities.grabR)}
        ready={true}
        active={false}
        remainingMs={0}
        totalMs={0}
        flashAt={0}
        activeColor="amber"
      >
        <span className="text-lg font-black">R</span>
      </AbilitySlot>
        </>
      )}
      <AbilitySlot
        label={t.battle.abilityDropWeapon}
        keyLabel={formatBindingLabel(abilities.dropWeapon)}
        ready={true}
        active={false}
        remainingMs={0}
        totalMs={0}
        flashAt={0}
        activeColor="amber"
      >
        <span className="text-sm font-black">DROP</span>
      </AbilitySlot>

      {slotAbility && (
        <AbilitySlot
          label={
            castCount > 1
              ? `${t.loadout.ability[slotAbility]} (+${castCount - 1})`
              : t.loadout.ability[slotAbility]
          }
          keyLabel={formatBindingLabel(abilities.slot4)}
          ready={true}
          active={false}
          remainingMs={0}
          totalMs={0}
          flashAt={0}
          activeColor="violet"
        >
          <span className="text-[10px] font-black leading-tight text-center px-0.5">
            CAST
          </span>
        </AbilitySlot>
      )}

      {slotItem && (
        <AbilitySlot
          label={
            itemCount > 1
              ? `${t.loadout.item[slotItem]} (+${itemCount - 1})`
              : t.loadout.item[slotItem]
          }
          keyLabel="PASS"
          ready={true}
          active={false}
          remainingMs={0}
          totalMs={0}
          flashAt={0}
          activeColor="sky"
          disabled={false}
        >
          <span className="text-[10px] font-black leading-tight text-center px-0.5">
            ITEM
          </span>
        </AbilitySlot>
      )}

      <div className="ability-bar__sep w-px h-12 bg-gray-700/80 mx-0.5 self-center" aria-hidden />

      <AbilitySlot
        label={t.battle.abilityReset}
        keyLabel={formatBindingLabel(abilities.reset)}
        ready={resetReady}
        remainingMs={resetRemainingMs}
        totalMs={RESET_COOLDOWN_MS}
        flashAt={lastResetFlash}
        activeColor="cyan"
      >
        <ResetIcon className="ability-icon ability-icon--bar" />
      </AbilitySlot>
    </div>
  );
}
