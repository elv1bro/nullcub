import type { ReactNode, SVGProps } from "react";

/** Стандартные слоты способностей — позже можно подменять кастомными. */
export type AbilityIconId = "dash" | "flip" | "freeze" | "reset" | "empty";

type SvgProps = SVGProps<SVGSVGElement> & { title?: string };

function SvgShell({
  children,
  className = "ability-icon",
  ...rest
}: SvgProps & { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      aria-hidden
      focusable="false"
      {...rest}
    >
      {children}
    </svg>
  );
}

export function DashIcon(props: SvgProps) {
  return (
    <SvgShell {...props}>
      <path
        d="M4 12h12M14 7l5 5-5 5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </SvgShell>
  );
}

export function FlipIcon(props: SvgProps) {
  return (
    <SvgShell {...props}>
      <path
        d="M12 4a8 8 0 1 1-7.8 6.2M12 4V1M12 4l2.5 2.5M12 20a8 8 0 1 1 7.8-6.2M12 20v3M12 20l-2.5-2.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </SvgShell>
  );
}

export function BraceIcon(props: SvgProps) {
  return (
    <SvgShell {...props}>
      <path
        d="M12 2l7 3v6c0 5-3 9-7 11-4-2-7-6-7-11V5l7-3z"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
    </SvgShell>
  );
}

export function ResetIcon(props: SvgProps) {
  return (
    <SvgShell {...props}>
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
    </SvgShell>
  );
}

export function EmptyAbilityIcon(props: SvgProps) {
  return (
    <SvgShell {...props}>
      <circle
        cx="12"
        cy="12"
        r="3"
        fill="currentColor"
        opacity="0.35"
      />
    </SvgShell>
  );
}

/** Реестр иконок — кастомные способности смогут регистрироваться сюда. */
const ABILITY_ICON_REGISTRY: Record<
  string,
  (props: SvgProps) => ReactNode
> = {
  dash: DashIcon,
  flip: FlipIcon,
  freeze: BraceIcon,
  brace: BraceIcon,
  reset: ResetIcon,
  empty: EmptyAbilityIcon,
};

export function registerAbilityIcon(
  id: string,
  render: (props: SvgProps) => ReactNode,
): void {
  ABILITY_ICON_REGISTRY[id] = render;
}

export function AbilityIcon({
  id,
  className = "ability-icon",
}: {
  id: string;
  className?: string;
}) {
  const render = ABILITY_ICON_REGISTRY[id] ?? EmptyAbilityIcon;
  return <>{render({ className })}</>;
}
