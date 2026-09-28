import { AbilityIcon } from "@/components/abilityIcons";
import { useViewportFlags } from "@/hooks/useViewportFlags";
import type { AbilityCooldownView } from "@/lib/usePlayerAbilities";
import {
  BRACE_COOLDOWN_MS,
  DASH_COOLDOWN_MS,
  FLIP_COOLDOWN_MS,
  RESET_COOLDOWN_MS,
} from "@/lib/battleTuning";
import { useSettings } from "@/settings/SettingsContext";
import {
  useCallback,
  useRef,
  type MutableRefObject,
  type PointerEvent,
  type ReactNode,
} from "react";

export type TouchMoveVec = { x: number; y: number };
export type TouchAbilityId = "dash" | "flip" | "freeze" | "reset";

const DEADZONE = 0.18;

const DEFAULT_TOTAL_MS: Record<TouchAbilityId, number> = {
  dash: DASH_COOLDOWN_MS,
  flip: FLIP_COOLDOWN_MS,
  freeze: BRACE_COOLDOWN_MS,
  reset: RESET_COOLDOWN_MS,
};

export type TouchAbilitySlot = {
  id: TouchAbilityId | string;
  /** Подпись для a11y / будущего тултипа. */
  label: string;
  /** id иконки в реестре (по умолчанию = id способности). */
  icon?: string;
  cls?: string;
  remainingMs?: number;
  ready?: boolean;
  totalMs?: number;
};

interface Props {
  /** Сюда пишем вектор в игровых координатах (left=+x, up=+y). */
  moveRef: MutableRefObject<TouchMoveVec>;
  onAbility?: (id: TouchAbilityId | string) => void;
  visible: boolean;
  /** Слоты 2×2 — позже можно подставлять кастомный loadout. */
  abilitySlots?: TouchAbilitySlot[];
  /** Кулдауны с десктопного AbilityBar / usePlayerAbilities. */
  cooldowns?: Pick<
    AbilityCooldownView,
    | "dashRemainingMs"
    | "flipRemainingMs"
    | "freezeRemainingMs"
    | "resetRemainingMs"
    | "dashReady"
    | "flipReady"
    | "freezeReady"
    | "resetReady"
  >;
}

function clampStick(dx: number, dy: number, radiusPx: number): TouchMoveVec {
  const max = Math.max(24, radiusPx);
  const len = Math.hypot(dx, dy);
  const nx = len > max ? (dx / len) * max : dx;
  const ny = len > max ? (dy / len) * max : dy;
  let x = -nx / max;
  let y = -ny / max;
  if (Math.abs(x) < DEADZONE) x = 0;
  if (Math.abs(y) < DEADZONE) y = 0;
  const mag = Math.hypot(x, y);
  if (mag > 1) {
    x /= mag;
    y /= mag;
  }
  return { x, y };
}

function formatCd(ms: number): string {
  if (ms <= 0) return "";
  const s = ms / 1000;
  if (s >= 10) return String(Math.ceil(s));
  return s.toFixed(1);
}

function defaultSlots(labels: {
  dash: string;
  flip: string;
  brace: string;
  reset: string;
}): TouchAbilitySlot[] {
  return [
    { id: "dash", label: labels.dash, icon: "dash", cls: "virtual-ability--dash" },
    { id: "flip", label: labels.flip, icon: "flip", cls: "virtual-ability--flip" },
    { id: "freeze", label: labels.brace, icon: "freeze", cls: "virtual-ability--brace" },
    { id: "reset", label: labels.reset, icon: "reset", cls: "virtual-ability--reset" },
  ];
}

function cooldownFor(
  id: string,
  cooldowns: Props["cooldowns"],
): { remainingMs: number; ready: boolean; totalMs: number } | null {
  if (!cooldowns) return null;
  switch (id) {
    case "dash":
      return {
        remainingMs: cooldowns.dashRemainingMs,
        ready: cooldowns.dashReady,
        totalMs: DASH_COOLDOWN_MS,
      };
    case "flip":
      return {
        remainingMs: cooldowns.flipRemainingMs,
        ready: cooldowns.flipReady,
        totalMs: FLIP_COOLDOWN_MS,
      };
    case "freeze":
      return {
        remainingMs: cooldowns.freezeRemainingMs,
        ready: cooldowns.freezeReady,
        totalMs: BRACE_COOLDOWN_MS,
      };
    case "reset":
      return {
        remainingMs: cooldowns.resetRemainingMs,
        ready: cooldowns.resetReady,
        totalMs: RESET_COOLDOWN_MS,
      };
    default:
      return null;
  }
}

/**
 * Twin-pad для телефона: слева движение, справа 4 способности (2×2) — иконки + CD.
 */
export function VirtualBattleStick({
  moveRef,
  onAbility,
  visible,
  abilitySlots,
  cooldowns,
}: Props) {
  const { t } = useSettings();
  const { coarse } = useViewportFlags();
  const baseRef = useRef<HTMLDivElement>(null);
  const knobRef = useRef<HTMLDivElement>(null);
  const activePointer = useRef<number | null>(null);

  const resetKnob = useCallback(() => {
    moveRef.current = { x: 0, y: 0 };
    const knob = knobRef.current;
    if (knob) knob.style.transform = "translate(-50%, -50%)";
  }, [moveRef]);

  const applyFromClient = useCallback(
    (clientX: number, clientY: number) => {
      const base = baseRef.current;
      const knob = knobRef.current;
      if (!base || !knob) return;
      const rect = base.getBoundingClientRect();
      const radius = Math.min(rect.width, rect.height) / 2 - 4;
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      const vec = clampStick(clientX - cx, clientY - cy, radius);
      moveRef.current = vec;
      knob.style.transform = `translate(calc(-50% + ${-vec.x * radius}px), calc(-50% + ${-vec.y * radius}px))`;
    },
    [moveRef],
  );

  const onPointerDown = (e: PointerEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    activePointer.current = e.pointerId;
    applyFromClient(e.clientX, e.clientY);
  };

  const onPointerMove = (e: PointerEvent<HTMLDivElement>) => {
    if (activePointer.current !== e.pointerId) return;
    e.preventDefault();
    applyFromClient(e.clientX, e.clientY);
  };

  const onPointerUp = (e: PointerEvent<HTMLDivElement>) => {
    if (activePointer.current !== e.pointerId) return;
    activePointer.current = null;
    resetKnob();
  };

  if (!visible || !coarse) return null;

  const abilities =
    abilitySlots ??
    defaultSlots({
      dash: t.battle.touchDash,
      flip: t.battle.touchFlip,
      brace: t.battle.touchBrace,
      reset: t.battle.touchReset,
    });

  return (
    <div className="virtual-battle-pad" aria-hidden={!visible}>
      <div
        ref={baseRef}
        className="virtual-stick"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        role="slider"
        aria-label={t.battle.touchStick}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <span ref={knobRef} className="virtual-stick__knob" />
      </div>

      {onAbility && (
        <div
          className="virtual-ability-grid"
          role="group"
          aria-label={t.battle.abilitiesHint}
        >
          {abilities.map((a) => {
            const fromView = cooldownFor(a.id, cooldowns);
            const remainingMs = a.remainingMs ?? fromView?.remainingMs ?? 0;
            const ready = a.ready ?? fromView?.ready ?? remainingMs <= 0;
            const totalMs =
              a.totalMs ??
              fromView?.totalMs ??
              DEFAULT_TOTAL_MS[a.id as TouchAbilityId] ??
              1;
            return (
              <AbilityButton
                key={a.id}
                slot={a}
                remainingMs={remainingMs}
                ready={ready}
                totalMs={totalMs}
                onFire={() => {
                  if (!ready) return;
                  onAbility(a.id);
                }}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

function AbilityButton({
  slot,
  remainingMs,
  ready,
  totalMs,
  onFire,
}: {
  slot: TouchAbilitySlot;
  remainingMs: number;
  ready: boolean;
  totalMs: number;
  onFire: () => void;
}): ReactNode {
  const progress = totalMs > 0 ? Math.min(1, Math.max(0, remainingMs / totalMs)) : 0;
  const cdLabel = formatCd(remainingMs);
  const aria = ready
    ? slot.label
    : `${slot.label}, ${cdLabel}s`;

  return (
    <button
      type="button"
      className={[
        "virtual-ability",
        slot.cls ?? "",
        ready ? "" : "virtual-ability--cooling",
      ]
        .filter(Boolean)
        .join(" ")}
      aria-label={aria}
      title={aria}
      aria-disabled={!ready}
      onPointerDown={(e) => {
        e.preventDefault();
        onFire();
      }}
    >
      <AbilityIcon
        id={slot.icon ?? slot.id}
        className="ability-icon ability-icon--touch"
      />
      {!ready && (
        <>
          <span
            className="virtual-ability__cd-mask"
            style={{
              // Снизу вверх «заливка» оставшегося CD.
              clipPath: `inset(${(1 - progress) * 100}% 0 0 0)`,
            }}
          />
          <span className="virtual-ability__cd">{cdLabel}</span>
        </>
      )}
    </button>
  );
}
