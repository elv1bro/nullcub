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
import { useSettings } from "@/settings/SettingsContext";

type Props = AbilityCooldownView & {
  disabled?: boolean;
  bindings?: AbilityBindings;
};

function DashIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-7 h-7" aria-hidden>
      <path
        d="M4 12h12M14 7l5 5-5 5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function FlipIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-7 h-7" aria-hidden>
      <path
        d="M12 4a8 8 0 1 1-7.8 6.2M12 4V1M12 4l2.5 2.5M12 20a8 8 0 1 1 7.8-6.2M12 20v3M12 20l-2.5-2.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function BraceIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-7 h-7" aria-hidden>
      <path
        d="M12 2l7 3v6c0 5-3 9-7 11-4-2-7-6-7-11V5l7-3z"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ResetIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-7 h-7" aria-hidden>
      <path
        d="M12 3v3M12 3a6 6 0 1 1-4.2 10.2M8 7l-2-2M8 7l2-2"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M8 12h8M10 9v6M14 9v6"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
      />
    </svg>
  );
}

function EmptySlotIcon() {
  return (
    <span className="text-xl font-black text-gray-600/80" aria-hidden>
      ·
    </span>
  );
}

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
        "relative flex flex-col items-center gap-1 select-none",
        enabled && (ready || active) ? "opacity-100" : "opacity-55",
      ].join(" ")}
      title={label}
    >
      <div
        className={[
          "relative w-14 h-14 rounded-xl border-2 flex items-center justify-center overflow-hidden transition-colors duration-150",
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
            <span className="absolute inset-0 flex items-center justify-center text-sm font-black tabular-nums text-white drop-shadow">
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
      <span className="text-[10px] font-ui uppercase tracking-wider text-gray-400">
        {keyLabel}
      </span>
      <span className="text-[10px] font-ui text-gray-500 max-w-16 text-center leading-tight">
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

  if (disabled) return null;

  const dashActive = dashActiveRemainingMs > 0;
  const freezeActive = freezeActiveRemainingMs > 0;

  return (
    <div className="flex items-end justify-center gap-3 pointer-events-none">
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
        <DashIcon />
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
        <FlipIcon />
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
        <BraceIcon />
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
        label={t.battle.abilitySlotEmpty}
        keyLabel={formatBindingLabel(abilities.slot4)}
        ready={false}
        disabled
        remainingMs={0}
        totalMs={0}
        flashAt={0}
      >
        <EmptySlotIcon />
      </AbilitySlot>

      <div className="w-px h-12 bg-gray-700/80 mx-0.5 self-center" aria-hidden />

      <AbilitySlot
        label={t.battle.abilityReset}
        keyLabel={formatBindingLabel(abilities.reset)}
        ready={resetReady}
        remainingMs={resetRemainingMs}
        totalMs={RESET_COOLDOWN_MS}
        flashAt={lastResetFlash}
        activeColor="cyan"
      >
        <ResetIcon />
      </AbilitySlot>
    </div>
  );
}
