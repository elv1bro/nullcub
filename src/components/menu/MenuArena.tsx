/**
 * Фон меню — тёплый «хаос-арены» без Matter / фонового боя.
 */
export function MenuArena() {
  return (
    <div className="menu-arena-canvas-wrap absolute inset-0" aria-hidden>
      <div className="menu-arena-chaos" />
    </div>
  );
}
