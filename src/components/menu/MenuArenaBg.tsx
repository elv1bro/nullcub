/** Декоративный фон «додзё» — пол и стены без Matter. */
export function MenuArenaBg() {
  return (
    <div
      className="fixed inset-0 pointer-events-none z-0 opacity-40"
      aria-hidden
      style={{
        background: `
          linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.35) 100%),
          repeating-linear-gradient(
            90deg,
            rgba(255,255,255,0.02) 0px,
            rgba(255,255,255,0.02) 1px,
            transparent 1px,
            transparent 48px
          ),
          repeating-linear-gradient(
            0deg,
            rgba(255,255,255,0.015) 0px,
            rgba(255,255,255,0.015) 1px,
            transparent 1px,
            transparent 48px
          )
        `,
      }}
    />
  );
}
